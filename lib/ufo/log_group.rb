# Use to automatically create the CloudWatch group.
# For some reason creating ECS does do this by default.
module Ufo
  class LogGroup
    include AwsService

    def initialize(task_definition, options)
      @task_definition, @options = task_definition, options
    end

    def create
      puts "Ensuring log group for #{@task_definition.color(:green)} task definition exists"
      return if @options[:noop]
      return if @options[:rollback] # dont need to create log group because previously deployed

      Ufo.check_task_definition!(@task_definition)
      task_def = JSON.load(IO.read(task_def_path))
      task_def["containerDefinitions"].each do |container_def|
        begin
          log_group_name = container_def["logConfiguration"]["options"]["awslogs-group"]
          puts "Log group name: #{log_group_name}"
        rescue NoMethodError
          # silence when the logConfiguration is not specified
        end

        create_log_group(log_group_name) if log_group_name
      end
    end

    def create_log_group(log_group_name)
      resp = cloudwatchlogs.describe_log_groups(log_group_name_prefix: log_group_name)
      exists = resp.log_groups.find { |lg| lg.log_group_name == log_group_name }
      cloudwatchlogs.create_log_group(log_group_name: log_group_name) unless exists
    end

    def task_def_path
      "#{Ufo.root}/.ufo/output/#{@task_definition}.json"
    end
  end
end
