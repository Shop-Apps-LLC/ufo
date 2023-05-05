module Ufo::Cfn::Stack::Builder::Resources::Scaling
  class Policy < Base
    def build
      return unless autoscaling_enabled?

      text =<<~EOL
        Type: AWS::ApplicationAutoScaling::ScalingPolicy
        Properties:
          PolicyName: !Sub "${AWS::StackName}-auto-scaling-policy"
          PolicyType: TargetTrackingScaling
          ScalingTargetId: !Ref ScalingTarget
          TargetTrackingScalingPolicyConfiguration:
            PredefinedMetricSpecification:
              PredefinedMetricType: #{autoscaling.predefined_metric_type}
            TargetValue: #{autoscaling.target_value}
      EOL

      attrs = Ufo::Yaml.load(text).deep_symbolize_keys
      props = attrs[:Properties]
      conf = props[:TargetTrackingScalingPolicyConfiguration]
      conf[:ScaleInCooldown] = autoscaling.scale_in_cooldown if autoscaling.scale_in_cooldown
      conf[:ScaleOutCooldown] = autoscaling.scale_out_cooldown if autoscaling.scale_out_cooldown

      if autoscaling.resource_label && autoscaling.predefined_metric_type == "ALBRequestCountPerTarget"
        attrs[:Properties][:TargetTrackingScalingPolicyConfiguration][:PredefinedMetricSpecification][:ResourceLabel] =  autoscaling.resource_label
      end

      attrs
    end
  end
end
