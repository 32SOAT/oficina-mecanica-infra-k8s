aws_region = "us-east-1"

vpc_cidr           = "10.20.0.0/16"
az_count           = 2
single_nat_gateway = true

cluster_version           = "1.36"
cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

node_instance_types = ["t3.medium"]
node_capacity_type  = "SPOT"
node_min_size       = 1
node_desired_size   = 1
node_max_size       = 3
node_disk_size      = 30
