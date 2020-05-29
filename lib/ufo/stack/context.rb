class Ufo::Stack
  class Context
    extend Memoist
    include Helper
    include Ufo::Settings

    attr_reader :stack_name
    def initialize(options)
      @options = options
      @task_definition = options[:task_definition]
      @service = options[:service]
      # no need to adjust @cluster or @stack_name because it was adjusted in Stack#initialize
      @cluster = options[:cluster].dup # Thor options are frozen, we thaw it because CustomProperties#substitute_variables does a sub!
      @stack_name = options[:stack_name]

      @stack = options[:stack]
      @new_stack = !@stack
    end

    def scope
      scope = Ufo::TemplateScope.new(Ufo::DSL::Helper.new, nil)
      # Add additional variable to scope for CloudFormation template.
      # Dirties the scope but needed.
      vars = {
        service: @service,
        cluster: @cluster,
        stack_name: @stack_name, # used in custom_properties
        container: container,
        # to reconstruct TaskDefinition in the CloudFormation template
        task_definition: @task_definition,
        rollback_definition_arn: @options[:rollback_definition_arn],
        # elb options remember that their 'state'
        create_elb: create_elb?, # helps set Ecs DependsOn
        elb_type: elb_type,
        subnet_mappings: subnet_mappings,
        create_route53: create_elb? && has_dns_name?,
        default_target_group_protocol: default_target_group_protocol,
        default_listener_protocol: default_listener_protocol,
        default_listener_ssl_protocol: default_listener_ssl_protocol,
        create_listener_ssl: create_listener_ssl?,
      }

      scope.assign_instance_variables(vars)
      scope
    end
    memoize :scope

    def has_dns_name?
      cfn.dig(:Dns, :Name) || cfn.dig(:dns, :name) # backwards compatiblity
    end

    def default_target_group_protocol
      return 'TCP' if elb_type == 'network'
      'HTTP'
    end

    def default_listener_protocol
      port = cfn.dig(:Listener, :Port) || cfn.dig(:listener, :port) # backwards compatiblity
      if elb_type == 'network'
        port == 443 ? 'TLS' : 'TCP'
      else
        port == 443 ? 'HTTPS' : 'HTTP'
      end
    end

    def default_listener_ssl_protocol
      elb_type == 'network' ? 'TLS' : 'HTTPS'
    end

    # if the configuration is set to anything then enable it
    def create_listener_ssl?
      cfn.dig(:ListenerSsl, :Port) || cfn.dig(:listener_ssl, :port) # backwards compatiblity
    end

    def create_elb?
      create_elb, _ = elb_options
      create_elb == "true" # convert to boolean
    end

    # If --elb is not set at all and is nil, then it defaults to creating the load balancer if the ecs service has
    # a container name "web".
    #
    # --elb '' - will not crete an elb
    # --elb 'auto' - creates an elb
    # --elb arn:... - will not create elb and use the existing target group
    #
    def elb_options
      case @options[:elb]
      when "auto", "true", "yes"
        create_elb = "true"
        elb_target_group = ""
      when "false", "0", "no"
        create_elb = "false"
        elb_target_group = ""
      when /^arn:aws:elasticloadbalancing.*targetgroup/
        create_elb = "false"
        elb_target_group = @options[:elb]
      when "", nil
        create_elb, elb_target_group = default_elb_options
      else
        puts "Invalid --elb option provided: #{@options[:elb].inspect}".color(:red)
        puts "Exiting."
        exit 1
      end
      [create_elb, elb_target_group]
    end

    def default_elb_options
      # cannot use :use_previous_value because need to know the create_elb value to
      # compile a template with the right DependsOn for the Ecs service
      unless @new_stack
        create_elb = get_parameter_value(@stack, "CreateElb")
        elb_target_group = get_parameter_value(@stack, "ElbTargetGroup")
        return [create_elb, elb_target_group]
      end

      # default is to create the load balancer is if container name is web
      # and no --elb option is provided
      create_elb = container[:name] == "web" ? "true" : "false"
      elb_target_group = ""
      [create_elb, elb_target_group]
    end

    def container
      task_definition = Builder::Resources::TaskDefinition::Reconstructor.new(@task_definition, @options[:rollback]).reconstruct

      container_def = task_definition["ContainerDefinitions"].first
      requires_compatibilities = task_definition["RequiresCompatibilities"]
      fargate = requires_compatibilities && requires_compatibilities == ["FARGATE"]
      network_mode = task_definition["NetworkMode"]

      mappings = container_def["PortMappings"] || []
      unless mappings.empty?
        port = mappings.first["ContainerPort"]
      end

      result =  {
        name: container_def["Name"],
        fargate: fargate,
        network_mode: network_mode, # awsvpc, bridge, etc
      }
      result[:port] = port if port
      result
    end
    memoize :container

    def get_parameter_value(stack, key)
      param = stack.parameters.find do |p|
        p.parameter_key == key
      end
      param.parameter_value if param
    end

    def scheduling_strategy
      unless @new_stack
        scheduling_strategy = get_parameter_value(@stack, "EcsSchedulingStrategy")
      end
      scheduling_strategy || 'REPLICA' # defaults to REPLICA
    end

    def reset_empty_eip_ids?
      # reset and remove eip allocation ids check
      @options[:elb_eip_ids] && @options[:elb_eip_ids].detect { |x| [' ', 'empty'].include?(x) }
    end

    def subnet_mappings
      return [] if reset_empty_eip_ids?

      elb_eip_ids = normalize_elb_eip_ids
      return build_subnet_mappings!(elb_eip_ids) unless elb_eip_ids.empty?

      unless @new_stack
        elb_eip_ids = get_parameter_value(@stack, "ElbEipIds").split(',')
        build_subnet_mappings(elb_eip_ids)
      end
    end

    def normalize_elb_eip_ids
      elb_eip_ids = @options[:elb_eip_ids] || []
      elb_eip_ids.uniq!
      elb_eip_ids
    end

    # Returns string, used as CloudFormation parameter.
    def elb_eip_ids
      return '' if reset_empty_eip_ids?

      elb_eip_ids = normalize_elb_eip_ids
      return elb_eip_ids.join(',') unless elb_eip_ids.empty?

      unless @new_stack
        return get_parameter_value(@stack, "ElbEipIds")
      end

      ''
    end

    def build_subnet_mappings!(allocations)
      unless allocations.size == network[:elb_subnets].size
        puts "ERROR: The allocation_ids must match in length to the subnets.".color(:red)
        puts "Please double check that .ufo/settings/network/#{settings.network_profile} has the same number of subnets as the eip allocation ids are you specifying."
        subnets = network[:elb_subnets]
        puts "Conigured subnets: #{subnets.inspect}"
        puts "Specified allocation ids: #{allocations.inspect}"
        exit 1
      end

      build_subnet_mappings(allocations)
    end

    def build_subnet_mappings(allocations)
      mappings = []
      allocations.sort.each_with_index do |allocation_id, i|
        mappings << [allocation_id, network[:elb_subnets][i]]
      end
      mappings
    end

    def elb_type
      # if option explicitly specified then change the elb type
      return @options[:elb_type] if @options[:elb_type]
      # user is trying to create a network load balancer if --elb-eip-ids is used
      elb_eip_ids = normalize_elb_eip_ids
      if !elb_eip_ids.empty?
        return "network"
      end

      # if not explicitly set, new stack will defeault to application load balancer
      if @new_stack # default for new stack
        return "application"
      end

      # find existing load balancer for type
      resp = cloudformation.describe_stack_resources(stack_name: @stack_name)
      resources = resp.stack_resources
      elb_resource = resources.find do |resource|
        resource.logical_resource_id == "Elb"
      end

      # In the case when stack exists and there is no elb resource, the elb type
      # doesnt really matter because the elb wont be created since the CreateElb
      # parameter is set to false. The elb type only needs to be set for the
      # template to validate.
      return "application" unless elb_resource

      resp = elb.describe_load_balancers(load_balancer_arns: [elb_resource.physical_resource_id])
      load_balancer = resp.load_balancers.first
      load_balancer.type
    end
    memoize :elb_type

  end
end
