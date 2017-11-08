variable "env" { type = "string" }
variable "cluster_name" { type = "string" }
variable "lifecycle_hook_heartbeat_timeout" { default = 900 }
variable "security_groups" { type = "list" }
variable "worker_ami" { default = "ami-a89d3ad2" }
variable "worker_asg_max_size" { default = 5 }
variable "worker_asg_min_size" { default = 3 }
variable "worker_instance_type" { default = "t2.medium" }
variable "worker_subnets" { type = "list" }
variable "discovery_srv" { type = "string" }
variable "kubelet_version" { type = "string" }
variable "cluster_dns" { type = "string" }
variable "ssl_bucket" { type = "string" }
variable "key_name" { type = "string" }
variable "worker_iam_profile" { type = "string" }
variable "root_volume_size" { default = 8 }
variable "addl_volume_size" { default = 250 }

# Needed if we ever want to implement autoscaling policy
# variable "worker_asg_namespace" {}
# variable "worker_asg_scale_in_cooldown" { default = 300 }
# variable "worker_asg_scale_in_qty" { default = -1 }
# variable "worker_asg_scale_in_threshold" { default = 64 }
# variable "worker_asg_scale_out_cooldown" { default = 300 }
# variable "worker_asg_scale_out_qty" { default = 1 }
# variable "worker_asg_scale_out_threshold" { default = 48 }
# variable "worker_queue" {}