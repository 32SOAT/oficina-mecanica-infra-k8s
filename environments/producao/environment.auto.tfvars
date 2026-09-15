aws_region = "us-east-1"

vpc_cidr           = "10.30.0.0/16"
az_count           = 3
single_nat_gateway = false

cluster_version           = "1.36"
cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

node_instance_types = ["m6i.large"]
node_capacity_type  = "ON_DEMAND"
node_min_size       = 2
node_desired_size   = 2
node_max_size       = 6
node_disk_size      = 50
