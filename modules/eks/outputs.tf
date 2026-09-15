output "cluster_name" {
  description = "Nome do cluster EKS."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "Endpoint da API Kubernetes."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Autoridade certificadora codificada em base64 para clientes Kubernetes."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "Security group primario criado pelo EKS para o cluster."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "database_client_security_group_id" {
  description = "Security group estavel usado para autorizar clientes do banco gerenciado."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "oidc_issuer_url" {
  description = "URL do emissor OIDC do cluster."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}
