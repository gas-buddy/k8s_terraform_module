data "template_file" "master_cloud_config" {
  count = "${var.master_instances}"

  template = "${file("${path.module}/master-cloud-config.yml.tpl")}"

  vars {
    discovery_srv = "${var.discovery_srv}"
    kubernetes_version = "${var.kubernetes_version}"
    cluster_dns = "${var.cluster_dns}"
    ssl_bucket = "${var.ssl_bucket}"
    flanneld_network = "${var.flanneld_network}"
    cluster_ip_range = "${var.cluster_ip_range}"
    node_name = "${var.env}-k8s-master-${count.index+1}"
    ip_address = "${element(var.master_ips, count.index)}"
  }
}

resource "aws_instance" "master" {
  count = "${var.master_instances}"

  ami = "${var.master_ami}"
  instance_type = "${var.master_instance_type}"
  key_name = "${var.key_name}"
  vpc_security_group_ids = ["${var.master_security_groups}"]
  subnet_id = "${element(var.master_subnets, count.index)}"
  user_data = "${element(data.template_file.master_cloud_config.*.rendered, count.index)}"
  iam_instance_profile = "${var.master_iam_profile}"
  private_ip = "${element(var.master_ips, count.index)}"

  source_dest_check = false
  monitoring = false

  tags {
    Name = "${var.env}-k8s-master-${count.index+1}"
    env = "${var.env}"
    "kubernetes.io/cluster/${var.cluster_name}" = "true"
    role = "etcd,apiserver"
    KubernetesCluster = "${var.cluster_name}"
    builtWith = "terraform"
  }

  root_block_device {
    volume_type = "gp2"
    volume_size = "${var.master_root_volume_size}"
  }
}

resource "aws_route53_record" "A" {
  count = "${var.master_instances}"

  zone_id = "${var.route53_zone_id}"
  name = "${var.env}-k8s-master-${count.index+1}.${var.discovery_srv}"
  type = "A"
  ttl = "300"

  records = ["${element(var.master_ips, count.index)}"]
}

resource "aws_route53_record" "SRV" {
  zone_id = "${var.route53_zone_id}"
  name = "_etcd-server-ssl._tcp.${var.discovery_srv}"
  type = "SRV"
  ttl = "300"

  records = [
    "0 0 2380 etcd1.staging.kz8s",
    "0 0 2380 etcd2.staging.kz8s",
    "0 0 2380 etcd3.staging.kz8s",
    "${formatlist("0 0 2380 %s", var.master_ips)}"
  ]
}

resource "aws_route53_record" "cluster-A" {
  zone_id = "${var.route53_zone_id}"
  name = "etcd.${var.discovery_srv}"
  type = "A"
  ttl = "300"

  records = [
    "172.30.10.10",
    "172.30.10.11",
    "172.30.10.12",
    "${var.master_ips}"
  ]
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

output "master_user_data" { value = "${data.template_file.master_cloud_config.rendered}" }
