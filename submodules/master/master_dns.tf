resource "aws_route53_record" "A" {
  count = "${var.instances}"

  zone_id = "${var.route53_zone_id}"
  name = "${var.env}-k8s-master-${count.index+1}.${var.discovery_srv}"
  type = "A"
  ttl = "300"

  records = ["${element(var.ips, count.index)}"]
}

variable "names" {
  default = [
    "k8s-master-1",
    "k8s-master-2",
    "k8s-master-3"
  ]
}

resource "aws_route53_record" "server_SRV" {
  zone_id = "${var.route53_zone_id}"
  name = "_etcd-server-ssl._tcp.${var.discovery_srv}"
  type = "SRV"
  ttl = "300"

  records = [
    "${formatlist("0 0 2380 %s.${var.discovery_srv}", var.legacy_names)}",
    "${formatlist("0 0 2380 ${var.env}-%s.${var.discovery_srv}", var.names)}"
  ]
}

resource "aws_route53_record" "client_SRV" {
  zone_id = "${var.route53_zone_id}"
  name = "_etcd-client-ssl._tcp.${var.discovery_srv}"
  type = "SRV"
  ttl = "300"

  records = [
    "${formatlist("0 0 2380 %s.${var.discovery_srv}", var.legacy_names)}",
    "${formatlist("0 0 2380 ${var.env}-%s.${var.discovery_srv}", var.names)}"
  ]
}

resource "aws_route53_record" "cluster-A" {
  zone_id = "${var.route53_zone_id}"
  name = "etcd.${var.discovery_srv}"
  type = "A"
  ttl = "300"

  records = [
    "${var.legacy_ips}",
    "${var.ips}"
  ]
}

resource "aws_route53_record" "CNAME" {
  zone_id = "${var.route53_zone_id}"
  name = "master.${var.discovery_srv}"
  type = "CNAME"
  ttl = "300"

  records = ["etcd.${var.discovery_srv}"]
}