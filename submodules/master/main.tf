data "template_file" "cloud_config" {
  count = "${var.instances}"

  template = "${file("${path.module}/master-cloud-config.yml.tpl")}"

  vars {
    discovery_srv = "${var.discovery_srv}"
    kubernetes_version = "${var.kubernetes_version}"
    cluster_dns = "${var.cluster_dns}"
    ssl_bucket = "${var.ssl_bucket}"
    flanneld_network = "${var.flanneld_network}"
    cluster_ip_range = "${var.cluster_ip_range}"
    node_name = "${var.env}-k8s-master-${count.index+1}"
    ip_address = "${element(var.ips, count.index)}"
  }
}

resource "aws_instance" "this" {
  count = "${var.instances}"

  ami = "${var.ami}"
  instance_type = "${var.instance_type}"
  key_name = "${var.key_name}"
  vpc_security_group_ids = ["${var.security_groups}"]
  subnet_id = "${element(var.private_subnets, count.index)}"
  user_data = "${element(data.template_file.cloud_config.*.rendered, count.index)}"
  iam_instance_profile = "${var.iam_profile}"
  private_ip = "${element(var.ips, count.index)}"

  source_dest_check = false
  monitoring = false

  tags {
    Name = "${var.env}-k8s-master-${count.index+1}"
    env = "${var.env}"
    # "kubernetes.io/cluster/${var.cluster_name}" = "true"
    role = "etcd,apiserver"
    KubernetesCluster = "${var.cluster_name}"
    builtWith = "terraform"
  }

  root_block_device {
    volume_type = "gp2"
    volume_size = "${var.root_volume_size}"
  }
}

resource "aws_elb" "this" {
  # name = "${var.env}-kubernetes-api"
  name = "k8s-apiserver-${var.cluster_name}"
  subnets = ["${var.public_subnets}"]
  instances = ["${aws_instance.this.*.id}"]
  idle_timeout = 3600
  cross_zone_load_balancing = true
  security_groups = ["${var.elb_security_group}"]

  health_check {
    target = "HTTP:8080/"
    timeout = 3
    interval = 30
    unhealthy_threshold = 2
    healthy_threshold = 2
  }

  listener {
    instance_port = 443
    instance_protocol = "tcp"
    lb_port = 443
    lb_protocol = "tcp"
  }

  tags {
    Name = "k8s-apiserver-${var.cluster_name}"
    builtWith = "terraform"
    KubernetesCluster = "${var.cluster_name}"
    env = "${var.env}"
    # "kubernetes.io/cluster/${var.cluster_name}" = "true"
    role = "apiserver"
  }
}

resource "aws_sns_topic" "masters" {
  name = "${var.env}-k8s-master"
}

output "user_data" { value = "${data.template_file.cloud_config.*.rendered}" }
