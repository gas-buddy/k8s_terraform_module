variable "env" { type = "string" }
variable "cluster_name" { type = "string" }
variable "lifecycle_hook_heartbeat_timeout" { default = 900 }
variable "discovery_srv" { type = "string" }
variable "kubernetes_version" { type = "string" }
variable "cluster_dns" { type = "string" }
variable "ssl_bucket" { type = "string" }
variable "key_name" { type = "string" }
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

# masters
variable "flanneld_network" { default = "10.2.0.0/16" }
variable "cluster_ip_range" { default = "10.3.0.0/24" }
variable "master_root_volume_size" { default = 8 }
variable "master_iam_profile" { type = "string" }
variable "master_ami" { default = "ami-a89d3ad2" }
variable "master_asg_max_size" { default = 3 }
variable "master_asg_min_size" { default = 3 }
variable "master_instance_type" { default = "t2.medium" }
variable "master_subnets" { type = "list" }
variable "master_security_groups" { type = "list" }

# workers
variable "worker_root_volume_size" { default = 8 }
variable "worker_iam_profile" { type = "string" }
variable "worker_ami" { default = "ami-a89d3ad2" }
variable "worker_asg_max_size" { default = 5 }
variable "worker_asg_min_size" { default = 4 }
variable "worker_instance_type" { default = "t2.medium" }
variable "worker_subnets" { type = "list" }
variable "worker_security_groups" { type = "list" }
