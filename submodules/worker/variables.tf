variable "env" { type = "string" }
variable "cluster_name" { type = "string" }
variable "lifecycle_hook_heartbeat_timeout" { default = 900 }
variable "discovery_srv" { type = "string" }
variable "kubernetes_version" { type = "string" }
variable "cluster_dns" { type = "string" }
variable "ssl_bucket" { type = "string" }
variable "key_name" { type = "string" }
variable "addl_volume_size" { default = 250 }
variable "route53_zone_id" { type = "string" }

# Needed if we ever want to implement autoscaling policy
# variable "worker_asg_namespace" {}
# variable "worker_asg_scale_in_cooldown" { default = 300 }
# variable "worker_asg_scale_in_qty" { default = -1 }
# variable "worker_asg_scale_in_threshold" { default = 64 }
# variable "worker_asg_scale_out_cooldown" { default = 300 }
# variable "worker_asg_scale_out_qty" { default = 1 }
# variable "worker_asg_scale_out_threshold" { default = 48 }
# variable "worker_queue" {}

variable "root_volume_size" { default = 8 }
variable "iam_profile" { type = "string" }
variable "ami" { default = "ami-a89d3ad2" }
variable "asg_max_size" { default = 8 }
variable "asg_min_size" { default = 4 }
variable "instance_type" { default = "m3.medium" }
variable "private_subnets" { type = "list" }
variable "public_subnets" { type = "list" }
variable "security_groups" { type = "list" }
