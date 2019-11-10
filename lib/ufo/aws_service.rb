require "aws-sdk-cloudformation"
require "aws-sdk-cloudwatchlogs"
require "aws-sdk-ec2"
require "aws-sdk-ecr"
require "aws-sdk-ecs"
require "aws-sdk-elasticloadbalancingv2"

require "aws_mfa_secure/ext/aws" # add MFA support

module Ufo
  module AwsService
    def cloudformation
      @cloudformation ||= Aws::CloudFormation::Client.new
    end

    def cloudwatchlogs
      @cloudwatchlogs ||= Aws::CloudWatchLogs::Client.new
    end

    def ec2
      @ec2 ||= Aws::EC2::Client.new
    end

    def ecr
      @ecr ||= Aws::ECR::Client.new
    end

    def ecs
      @ecs ||= Aws::ECS::Client.new
    end

    def elb
      @elb ||= Aws::ElasticLoadBalancingV2::Client.new
    end
  end
end
