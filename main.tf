module "worker" {
  source = "submodules/worker"

  env = "${var.env}"
  cluster_name = "${var.cluster_name}"

  discovery_srv = "${var.discovery_srv}"
  route53_zone_id = "${var.route53_zone_id}"

  kubernetes_version = "${var.kubernetes_version}"
  cluster_dns = "${var.cluster_dns}"
  ssl_bucket = "${var.ssl_bucket}"
  root_volume_size = "${var.worker_root_volume_size}"
  iam_profile = "${var.worker_iam_profile}"
  key_name = "${var.key_name}"
  security_groups = ["${var.worker_security_groups}"]
  private_subnets = ["${var.worker_subnets}"]
  public_subnets = ["${var.public_subnets}"]
  instance_type = "${var.worker_instance_type}"
}

module "master" {
  source = "submodules/master"

  env = "${var.env}"
  cluster_name = "${var.cluster_name}"

  discovery_srv = "${var.discovery_srv}"
  route53_zone_id = "${var.route53_zone_id}"

  kubernetes_version = "${var.kubernetes_version}"
  cluster_dns = "${var.cluster_dns}"
  ssl_bucket = "${var.ssl_bucket}"
  root_volume_size = "${var.master_root_volume_size}"
  iam_profile = "${var.master_iam_profile}"
  key_name = "${var.key_name}"
  security_groups = ["${var.master_security_groups}"]
  private_subnets = ["${var.master_subnets}"]
  public_subnets = ["${var.public_subnets}"]
  instance_type = "${var.master_instance_type}"

  elb_security_group = "${var.elb_security_group}"

  ips = ["${var.master_ips}"]

}
