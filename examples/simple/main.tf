module "k8s" {
  source = "../../"

  env = "stg"
  cluster_name = "staging"

  discovery_srv = "staging.k8s"
  kubernetes_version = "v1.5.3_coreos.0"
  cluster_dns = "10.3.0.10"
  ssl_bucket = "some_s3_bucket"
  worker_root_volume_size = 8
  master_root_volume_size = 8
  worker_iam_profile = "my_worker_iam_profile_name"
  master_iam_profile = "my_master_iam_profile_name"
  key_name = "your_ops_key"
  worker_security_groups = ["sg-01234567"]
  master_security_groups = ["sg-01234567"]
  worker_subnets = ["subnet-01234567","subnet-abcdefgh"]
  master_subnets = ["subnet-01234567","subnet-abcdefgh"]
}
