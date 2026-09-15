# Each assertion catches a topology, isolation, addressing, or ownership regression.
# AWS calls are mocked; Terraform still evaluates the real module graph and expressions.
mock_provider "aws" {
  override_during = plan

  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c"]
    }
  }

  mock_resource "aws_internet_gateway" {
    defaults = {
      id = "igw-test"
    }
  }

  mock_resource "aws_nat_gateway" {
    defaults = {
      id = "nat-test"
    }
  }
}

variables {
  project_name       = "oficina-mecanica"
  environment        = "homologacao"
  vpc_cidr           = "10.20.0.0/16"
  az_count           = 2
  single_nat_gateway = true
  tags               = { CostCenter = "platform" }
}

run "network_has_isolated_database_tier" {
  command = plan

  assert {
    condition     = length(aws_subnet.public) == 2 && length(aws_subnet.private) == 2 && length(aws_subnet.database) == 2
    error_message = "Network must create one public, private, and database subnet per selected AZ."
  }

  assert {
    condition = (
      [for subnet in aws_subnet.public : subnet.cidr_block] == ["10.20.0.0/20", "10.20.16.0/20"] &&
      [for subnet in aws_subnet.private : subnet.cidr_block] == ["10.20.32.0/20", "10.20.48.0/20"] &&
      [for subnet in aws_subnet.database : subnet.cidr_block] == ["10.20.64.0/20", "10.20.80.0/20"]
    )
    error_message = "Subnet CIDRs must preserve the legacy public/private/database cidrsubnet allocation."
  }

  assert {
    condition = (
      [for subnet in aws_subnet.public : subnet.availability_zone] == ["us-east-1a", "us-east-1b"] &&
      [for subnet in aws_subnet.private : subnet.availability_zone] == ["us-east-1a", "us-east-1b"] &&
      [for subnet in aws_subnet.database : subnet.availability_zone] == ["us-east-1a", "us-east-1b"]
    )
    error_message = "Every subnet tier must use the same selected availability zones."
  }

  assert {
    condition = toset(keys(aws_route.default)) == toset([
      "public",
      "private-0",
      "private-1"
    ])
    error_message = "Only public and private tiers may have managed default routes; the database route table must have none."
  }

  assert {
    condition = (
      aws_route.default["public"].destination_cidr_block == "0.0.0.0/0" &&
      aws_route.default["public"].gateway_id == aws_internet_gateway.this.id
    )
    error_message = "Only the public tier must route directly through the internet gateway."
  }

  assert {
    condition = alltrue([
      for index in range(var.az_count) :
      aws_route.default["private-${index}"].destination_cidr_block == "0.0.0.0/0" &&
      aws_route.default["private-${index}"].nat_gateway_id == aws_nat_gateway.this[var.single_nat_gateway ? 0 : index].id
    ])
    error_message = "Each private route table must send its default route through a NAT gateway."
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 1 && length(aws_eip.nat) == 1
    error_message = "single_nat_gateway=true must create exactly one NAT gateway and address."
  }

  assert {
    condition = (
      alltrue([for subnet in aws_subnet.public : !subnet.map_public_ip_on_launch]) &&
      alltrue([for subnet in aws_subnet.private : !subnet.map_public_ip_on_launch]) &&
      alltrue([for subnet in aws_subnet.database : !subnet.map_public_ip_on_launch])
    )
    error_message = "No subnet may assign public IP addresses automatically; public routing is explicit through the internet gateway."
  }

  assert {
    condition = (
      aws_subnet.public[0].tags["Name"] == "oficina-mecanica-homologacao-public-us-east-1a" &&
      aws_subnet.private[0].tags["Name"] == "oficina-mecanica-homologacao-private-us-east-1a" &&
      aws_subnet.database[0].tags["Name"] == "oficina-mecanica-homologacao-database-us-east-1a" &&
      aws_subnet.public[0].tags["kubernetes.io/role/elb"] == "1" &&
      aws_subnet.private[0].tags["kubernetes.io/role/internal-elb"] == "1" &&
      aws_subnet.public[0].tags["kubernetes.io/cluster/oficina-mecanica-homologacao"] == "shared"
    )
    error_message = "Subnet names and Kubernetes discovery tags must preserve the legacy contract."
  }

  assert {
    condition = alltrue([
      for tags in concat(
        [aws_vpc.this.tags, aws_internet_gateway.this.tags, aws_route_table.public.tags, aws_route_table.database.tags],
        [for item in aws_subnet.public : item.tags],
        [for item in aws_subnet.private : item.tags],
        [for item in aws_subnet.database : item.tags],
        [for item in aws_eip.nat : item.tags],
        [for item in aws_nat_gateway.this : item.tags],
        [for item in aws_route_table.private : item.tags]
      ) :
      tags["Project"] == "oficina-mecanica" &&
      tags["Environment"] == "homologacao" &&
      tags["ManagedBy"] == "terraform" &&
      tags["CostCenter"] == "platform"
    ])
    error_message = "All taggable network resources must carry mandatory ownership tags and caller tags."
  }

  assert {
    condition = (
      output.private_subnet_cidrs == ["10.20.32.0/20", "10.20.48.0/20"] &&
      output.database_subnet_cidrs == ["10.20.64.0/20", "10.20.80.0/20"] &&
      length(output.public_subnet_ids) == 2 &&
      length(output.private_subnet_ids) == 2 &&
      length(output.database_subnet_ids) == 2
    )
    error_message = "Network outputs must expose each subnet tier and its consumer CIDRs."
  }
}

run "network_supports_one_nat_per_az" {
  command = plan

  variables {
    az_count           = 3
    single_nat_gateway = false
  }

  override_resource {
    target          = aws_subnet.public[0]
    override_during = plan
    values          = { id = "subnet-public-a" }
  }

  override_resource {
    target          = aws_subnet.public[1]
    override_during = plan
    values          = { id = "subnet-public-b" }
  }

  override_resource {
    target          = aws_subnet.public[2]
    override_during = plan
    values          = { id = "subnet-public-c" }
  }

  override_resource {
    target          = aws_route_table.private[0]
    override_during = plan
    values          = { id = "rtb-private-a" }
  }

  override_resource {
    target          = aws_route_table.private[1]
    override_during = plan
    values          = { id = "rtb-private-b" }
  }

  override_resource {
    target          = aws_route_table.private[2]
    override_during = plan
    values          = { id = "rtb-private-c" }
  }

  override_resource {
    target          = aws_nat_gateway.this[0]
    override_during = plan
    values          = { id = "nat-a" }
  }

  override_resource {
    target          = aws_nat_gateway.this[1]
    override_during = plan
    values          = { id = "nat-b" }
  }

  override_resource {
    target          = aws_nat_gateway.this[2]
    override_during = plan
    values          = { id = "nat-c" }
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 3 && length(aws_route_table.private) == 3
    error_message = "single_nat_gateway=false must create one NAT gateway and private route table per AZ."
  }

  assert {
    condition = alltrue([
      for index, suffix in ["a", "b", "c"] :
      aws_nat_gateway.this[index].subnet_id == "subnet-public-${suffix}" &&
      aws_route.default["private-${index}"].route_table_id == "rtb-private-${suffix}" &&
      aws_route.default["private-${index}"].nat_gateway_id == "nat-${suffix}"
    ])
    error_message = "Each private route table must use the NAT gateway in the public subnet from the same AZ."
  }
}

run "reject_too_few_availability_zones" {
  command = plan

  variables { az_count = 1 }

  expect_failures = [var.az_count]
}

run "reject_too_many_availability_zones" {
  command = plan

  variables { az_count = 4 }

  expect_failures = [var.az_count]
}

run "reject_cidr_too_small_for_all_tiers" {
  command = plan

  variables { vpc_cidr = "10.20.0.0/30" }

  expect_failures = [var.vpc_cidr]
}
