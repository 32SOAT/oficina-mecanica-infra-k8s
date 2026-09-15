output "parameter_names" {
  description = "Nomes exatos dos parametros publicados pelo contrato."
  value       = sort([for parameter in aws_ssm_parameter.platform : parameter.name])
}
