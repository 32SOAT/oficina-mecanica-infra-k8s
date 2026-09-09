output "vpc_id" {
  description = "ID da VPC criada."
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "IDs das subnets publicas."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs das subnets privadas."
  value       = aws_subnet.private[*].id
}

output "database_subnet_ids" {
  description = "IDs das subnets isoladas de banco."
  value       = aws_subnet.database[*].id
}

output "private_subnet_cidrs" {
  description = "CIDRs das subnets privadas."
  value       = local.private_subnet_cidrs
}

output "database_subnet_cidrs" {
  description = "CIDRs das subnets isoladas de banco."
  value       = local.database_subnet_cidrs
}
