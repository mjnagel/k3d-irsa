output "oidc_issuer_url" {
  description = "The OIDC issuer URL"
  value       = "https://${aws_s3_bucket.oidc.bucket_regional_domain_name}"
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket created for OIDC"
  value       = aws_s3_bucket.oidc.id
}

output "oidc_provider_arn" {
  description = "The ARN of the OIDC provider"
  value       = aws_iam_openid_connect_provider.oidc.arn
}

output "private_key_path" {
  description = "Path to the generated private key file"
  value       = local_file.private_key.filename
}

output "public_key_path" {
  description = "Path to the generated public key file"
  value       = local_file.public_key.filename
}

output "demo_role_arn" {
  description = "ARN of the demo IAM role"
  value       = var.deploy_demo_resources ? aws_iam_role.demo[0].arn : ""
}

output "demo_resources_enabled" {
  description = "Whether demo resources were deployed"
  value       = var.deploy_demo_resources
}

output "next_steps" {
  description = "Next steps after applying the configuration"
  value       = <<-EOT
    
    Next steps:
    1. Create the k3d cluster with the following command:
       ${local.k3d_create_command}
    
    2. Deploy the IRSA webhook:
       helm upgrade -i irsa ../chart/ -n irsa --create-namespace --wait --set podIdentityWebhook.config.region=${data.aws_region.current.region}
  EOT
}
