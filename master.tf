data "template_file" "master_cloud_config" {
  template = "${file("${path.module}/master-cloud-config.yml.tpl")}"

  vars {
    discovery_srv = "${var.discovery_srv}"
    kubernetes_version = "${var.kubernetes_version}"
    cluster_dns = "${var.cluster_dns}"
    ssl_bucket = "${var.ssl_bucket}"
    flanneld_network = "${var.flanneld_network}"
    cluster_ip_range = "${var.cluster_ip_range}"
  }
}

resource "aws_launch_configuration" "masters" {
  name_prefix = "${var.env}-k8s-master-"
  image_id = "${var.master_ami}"
  instance_type = "${var.master_instance_type}"
  security_groups = ["${var.master_security_groups}"]
  user_data = "${data.template_file.master_cloud_config.rendered}"
  iam_instance_profile = "${var.master_iam_profile}"
  key_name = "${var.key_name}"
  enable_monitoring = true

  root_block_device {
    volume_type = "gp2"
    volume_size = "${var.master_root_volume_size}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudformation_stack" "masters_asg" {
  name = "${var.env}-k8s-master"
  template_body = <<EOF
{
  "Resources": {
    "AutoScalingGroup": {
      "Type": "AWS::AutoScaling::AutoScalingGroup",
      "Properties": {
        "Cooldown": 300,
        "HealthCheckType": "EC2",
        "HealthCheckGracePeriod": 0,
        "LaunchConfigurationName": "${aws_launch_configuration.masters.name}",
        "MaxSize": "${var.master_asg_max_size}",
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
        "MinSize": "${var.master_asg_min_size}",
        "Tags": [
          {
            "Key": "Name",
            "Value": "${var.env}-k8s-master",
            "PropagateAtLaunch": true
          },
          {
            "Key": "env",
            "Value": "${var.env}",
            "PropagateAtLaunch": true
          },
          {
            "Key": "role",
            "Value": "master",
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
        "VPCZoneIdentifier": ${jsonencode(var.master_subnets)}
      },
      "UpdatePolicy": {
        "AutoScalingRollingUpdate": {
          "MinInstancesInService": "${var.master_asg_min_size}",
          "MaxBatchSize": "2",
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

# resource "aws_autoscaling_policy" "masters_remove_capacity" {
#   name = "${var.env}-${var.index}-masters-${var.site}-remove-capacity"
#   scaling_adjustment = "${var.master_asg_scale_in_qty}"
#   adjustment_type = "ChangeInCapacity"
#   cooldown = "${var.master_asg_scale_in_cooldown}"
#   autoscaling_group_name = "${aws_cloudformation_stack.masters_asg.outputs["AsgName"]}"
# }

# resource "aws_cloudwatch_metric_alarm" "masters_remove_capacity" {
#   alarm_name = "${var.env}-${var.index}-masters-${var.site}-remove-capacity"
#   comparison_operator = "GreaterThanOrEqualToThreshold"
#   evaluation_periods = 2
#   metric_name = "v1.travis.rabbitmq.consumers.builds.${var.master_queue}.headroom"
#   namespace = "${var.master_asg_namespace}"
#   period = 60
#   statistic = "Maximum"
#   threshold = "${var.master_asg_scale_in_threshold}"
#   alarm_actions = ["${aws_autoscaling_policy.masters_remove_capacity.arn}"]
# }

# resource "aws_autoscaling_policy" "masters_add_capacity" {
#   name = "${var.env}-${var.index}-masters-${var.site}-add-capacity"
#   scaling_adjustment = "${var.master_asg_scale_out_qty}"
#   adjustment_type = "ChangeInCapacity"
#   cooldown = "${var.master_asg_scale_out_cooldown}"
#   autoscaling_group_name = "${aws_cloudformation_stack.masters_asg.outputs["AsgName"]}"
# }

# resource "aws_cloudwatch_metric_alarm" "masters_add_capacity" {
#   alarm_name = "${var.env}-${var.index}-masters-${var.site}-add-capacity"
#   comparison_operator = "LessThanThreshold"
#   evaluation_periods = 2
#   metric_name = "v1.travis.rabbitmq.consumers.builds.${var.master_queue}.headroom"
#   namespace = "${var.master_asg_namespace}"
#   period = 60
#   statistic = "Maximum"
#   threshold = "${var.master_asg_scale_out_threshold}"
#   alarm_actions = ["${aws_autoscaling_policy.masters_add_capacity.arn}"]
# }

resource "aws_sns_topic" "masters" {
  name = "${var.env}-k8s-master"
}

resource "aws_iam_role" "masters_sns" {
  name = "${var.env}-k8s-master-sns"
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

resource "aws_iam_role_policy" "masters_sns" {
  name = "${var.env}-k8s-master-sns"
  role = "${aws_iam_role.masters_sns.id}"
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

resource "aws_autoscaling_lifecycle_hook" "masters_launching" {
  name = "${var.env}-k8s-master-launching"
  autoscaling_group_name = "${aws_cloudformation_stack.masters_asg.outputs["AsgName"]}"
  default_result = "CONTINUE"
  heartbeat_timeout = "${var.lifecycle_hook_heartbeat_timeout}"
  lifecycle_transition = "autoscaling:EC2_INSTANCE_LAUNCHING"
  notification_target_arn = "${aws_sns_topic.masters.arn}"
  role_arn = "${aws_iam_role.masters_sns.arn}"
}

resource "aws_autoscaling_lifecycle_hook" "masters_terminating" {
  name = "${var.env}-k8s-master-terminating"
  autoscaling_group_name = "${aws_cloudformation_stack.masters_asg.outputs["AsgName"]}"
  default_result = "CONTINUE"
  heartbeat_timeout = "${var.lifecycle_hook_heartbeat_timeout}"
  lifecycle_transition = "autoscaling:EC2_INSTANCE_TERMINATING"
  notification_target_arn = "${aws_sns_topic.masters.arn}"
  role_arn = "${aws_iam_role.masters_sns.arn}"
}

output "master_user_data" { value = "${data.template_file.master_cloud_config.rendered}" }
