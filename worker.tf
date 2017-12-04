data "template_file" "worker_cloud_config" {
  template = "${file("${path.module}/worker-cloud-config.yml.tpl")}"

  vars {
    discovery_srv = "${var.discovery_srv}"
    kubernetes_version = "${var.kubernetes_version}"
    cluster_dns = "${var.cluster_dns}"
    ssl_bucket = "${var.ssl_bucket}"
  }
}

resource "aws_launch_configuration" "workers" {
  name_prefix = "${var.env}-k8s-worker-"
  image_id = "${var.worker_ami}"
  instance_type = "${var.worker_instance_type}"
  security_groups = ["${var.worker_security_groups}"]
  user_data = "${data.template_file.worker_cloud_config.rendered}"
  iam_instance_profile = "${var.worker_iam_profile}"
  key_name = "${var.key_name}"
  enable_monitoring = true

  root_block_device {
    volume_type = "gp2"
    volume_size = "${var.worker_root_volume_size}"
  }

  ebs_block_device {
    device_name = "/dev/xvdf"
    volume_type = "gp2"
    volume_size = "${var.addl_volume_size}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudformation_stack" "workers_asg" {
  name = "${var.env}-k8s-worker"
  template_body = <<EOF
{
  "Resources": {
    "AutoScalingGroup": {
      "Type": "AWS::AutoScaling::AutoScalingGroup",
      "Properties": {
        "Cooldown": 300,
        "HealthCheckType": "EC2",
        "HealthCheckGracePeriod": 120,
        "LaunchConfigurationName": "${aws_launch_configuration.workers.name}",
        "MaxSize": "${var.worker_asg_max_size}",
        "MetricsCollection": [
          {
            "Granularity": "1Minute",
            "Metrics": [
              "GroupMinSize",
              "GroupMaxSize",
              "GroupDesiredCapacity",
              "GroupInServiceInstances",
              "GroupPendingInstances",
              "GroupStandbyInstances",
              "GroupTerminatingInstances",
              "GroupTotalInstances"
            ]
          }
        ],
        "MinSize": "${var.worker_asg_min_size}",
        "Tags": [
          {
            "Key": "Name",
            "Value": "${var.env}-k8s-worker",
            "PropagateAtLaunch": true
          },
          {
            "Key": "env",
            "Value": "${var.env}",
            "PropagateAtLaunch": true
          },
          {
            "Key": "role",
            "Value": "worker",
            "PropagateAtLaunch": true
          },
          {
            "Key": "kubernetes.io/cluster/${var.cluster_name}",
            "Value": "true",
            "PropagateAtLaunch": true
          },
          {
            "Key": "KubernetesCluster",
            "Value": "${var.cluster_name}",
            "PropagateAtLaunch": true
          }
        ],
        "TerminationPolicies": [
          "OldestLaunchConfiguration",
          "OldestInstance",
          "Default"
        ],
        "VPCZoneIdentifier": ${jsonencode(var.worker_subnets)}
      },
      "UpdatePolicy": {
        "AutoScalingRollingUpdate": {
          "MinInstancesInService": "${var.worker_asg_min_size}",
          "MaxBatchSize": "1",
          "PauseTime": "PT0S"
        }
      }
    }
  },
  "Outputs": {
    "AsgName": {
      "Description": "The name of the auto scaling group",
      "Value": {
        "Ref": "AutoScalingGroup"
      }
    }
  }
}
EOF
}

# This might be useful one day...

# resource "aws_autoscaling_policy" "workers_remove_capacity" {
#   name = "${var.env}-${var.index}-workers-${var.site}-remove-capacity"
#   scaling_adjustment = "${var.worker_asg_scale_in_qty}"
#   adjustment_type = "ChangeInCapacity"
#   cooldown = "${var.worker_asg_scale_in_cooldown}"
#   autoscaling_group_name = "${aws_cloudformation_stack.workers_asg.outputs["AsgName"]}"
# }

# resource "aws_cloudwatch_metric_alarm" "workers_remove_capacity" {
#   alarm_name = "${var.env}-${var.index}-workers-${var.site}-remove-capacity"
#   comparison_operator = "GreaterThanOrEqualToThreshold"
#   evaluation_periods = 2
#   metric_name = "v1.travis.rabbitmq.consumers.builds.${var.worker_queue}.headroom"
#   namespace = "${var.worker_asg_namespace}"
#   period = 60
#   statistic = "Maximum"
#   threshold = "${var.worker_asg_scale_in_threshold}"
#   alarm_actions = ["${aws_autoscaling_policy.workers_remove_capacity.arn}"]
# }

# resource "aws_autoscaling_policy" "workers_add_capacity" {
#   name = "${var.env}-${var.index}-workers-${var.site}-add-capacity"
#   scaling_adjustment = "${var.worker_asg_scale_out_qty}"
#   adjustment_type = "ChangeInCapacity"
#   cooldown = "${var.worker_asg_scale_out_cooldown}"
#   autoscaling_group_name = "${aws_cloudformation_stack.workers_asg.outputs["AsgName"]}"
# }

# resource "aws_cloudwatch_metric_alarm" "workers_add_capacity" {
#   alarm_name = "${var.env}-${var.index}-workers-${var.site}-add-capacity"
#   comparison_operator = "LessThanThreshold"
#   evaluation_periods = 2
#   metric_name = "v1.travis.rabbitmq.consumers.builds.${var.worker_queue}.headroom"
#   namespace = "${var.worker_asg_namespace}"
#   period = 60
#   statistic = "Maximum"
#   threshold = "${var.worker_asg_scale_out_threshold}"
#   alarm_actions = ["${aws_autoscaling_policy.workers_add_capacity.arn}"]
# }

resource "aws_sns_topic" "workers" {
  name = "${var.env}-k8s-worker"
}

resource "aws_iam_role" "workers_sns" {
  name = "${var.env}-k8s-worker-sns"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Effect": "Allow",
      "Principal": {
        "Service": "autoscaling.amazonaws.com"
      }
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "workers_sns" {
  name = "${var.env}-k8s-worker-sns"
  role = "${aws_iam_role.workers_sns.id}"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "sqs:SendMessage",
        "sqs:GetQueueUrl",
        "sns:Publish"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_autoscaling_lifecycle_hook" "workers_launching" {
  name = "${var.env}-k8s-worker-launching"
  autoscaling_group_name = "${aws_cloudformation_stack.workers_asg.outputs["AsgName"]}"
  default_result = "CONTINUE"
  heartbeat_timeout = "${var.lifecycle_hook_heartbeat_timeout}"
  lifecycle_transition = "autoscaling:EC2_INSTANCE_LAUNCHING"
  notification_target_arn = "${aws_sns_topic.workers.arn}"
  role_arn = "${aws_iam_role.workers_sns.arn}"
}

resource "aws_autoscaling_lifecycle_hook" "workers_terminating" {
  name = "${var.env}-k8s-worker-terminating"
  autoscaling_group_name = "${aws_cloudformation_stack.workers_asg.outputs["AsgName"]}"
  default_result = "CONTINUE"
  heartbeat_timeout = "${var.lifecycle_hook_heartbeat_timeout}"
  lifecycle_transition = "autoscaling:EC2_INSTANCE_TERMINATING"
  notification_target_arn = "${aws_sns_topic.workers.arn}"
  role_arn = "${aws_iam_role.workers_sns.arn}"
}

output "worker_user_data" { value = "${data.template_file.worker_cloud_config.rendered}" }
