variable "aws_region" {
  description = "AWS region to create resources in"
  type        = string
  default     = "us-west-1"
}

variable "bucket_name" {
  description = "Globally unique name for the S3 bucket that will store OIDC discovery documents"
  type        = string
}

variable "oidc_client_id_list" {
  description = "List of client IDs (audiences) for the OIDC provider"
  type        = list(string)
  default     = ["irsa"]
}

variable "deploy_demo_resources" {
  description = "Whether to deploy demo resources (IAM role, policy, etc.) for testing IRSA"
  type        = bool
  default     = false
}

variable "permissions_boundary_arn" {
  description = "ARN of the IAM policy that will be used as the permissions boundary for the demo role"
  type        = string
  default     = null
}
