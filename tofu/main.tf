data "aws_region" "current" {}

# Generate RSA key pair for OIDC
resource "tls_private_key" "oidc" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Create S3 bucket for OIDC discovery documents
resource "aws_s3_bucket" "oidc" {
  bucket = var.bucket_name

  tags = {
    Name = "${var.bucket_name}-oidc"
  }
  force_destroy = true
}

resource "aws_s3_bucket_ownership_controls" "oidc" {
  bucket = aws_s3_bucket.oidc.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "oidc" {
  bucket = aws_s3_bucket.oidc.id

  # Allow public access to the bucket
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Create OIDC discovery document
resource "local_file" "discovery_json" {
  content = jsonencode({
    issuer                                = "https://${aws_s3_bucket.oidc.bucket_regional_domain_name}"
    jwks_uri                              = "https://${aws_s3_bucket.oidc.bucket_regional_domain_name}/keys.json"
    authorization_endpoint                = "urn:kubernetes:programmatic_authorization"
    response_types_supported              = ["id_token"]
    subject_types_supported               = ["public"]
    id_token_signing_alg_values_supported = ["RS256"]
    claims_supported                      = ["sub", "iss"]
  })

  filename = "${path.module}/discovery.json"
}

# Get key ID and modulus using external scripts
data "external" "key_id" {
  program = ["bash", "${path.module}/key_id.sh", tls_private_key.oidc.public_key_pem]
}

data "external" "key_modulus" {
  program = ["bash", "${path.module}/key_modulus.sh", tls_private_key.oidc.public_key_pem]
}

# Create keys.json for OIDC
resource "local_file" "keys_json" {
  content = jsonencode({
    keys = [{
      use = "sig"
      kty = "RSA"
      kid = data.external.key_id.result.key_id
      alg = "RS256"
      n   = data.external.key_modulus.result.modulus
      e   = "AQAB"
    }]
  })

  filename = "${path.module}/keys.json"
}

# Upload OIDC documents to S3
resource "aws_s3_object" "discovery_json" {
  depends_on = [
    aws_s3_bucket_public_access_block.oidc,
    local_file.discovery_json
  ]

  bucket       = aws_s3_bucket.oidc.id
  key          = ".well-known/openid-configuration"
  source       = local_file.discovery_json.filename
  content_type = "application/json"
  acl          = "public-read"
}

resource "aws_s3_object" "keys_json" {
  depends_on = [
    aws_s3_bucket_public_access_block.oidc,
    local_file.keys_json
  ]

  bucket       = aws_s3_bucket.oidc.id
  key          = "keys.json"
  source       = local_file.keys_json.filename
  content_type = "application/json"
  acl          = "public-read"
}

# Create OIDC provider
resource "aws_iam_openid_connect_provider" "oidc" {
  url            = "https://${aws_s3_bucket.oidc.bucket_regional_domain_name}"
  client_id_list = var.oidc_client_id_list

  # For demo purposes, we're using a static thumbprint
  # In production, you should use the actual certificate thumbprint
  thumbprint_list = ["demodemodemodemodemodemodemodemodemodemo"]

  depends_on = [
    aws_s3_object.discovery_json,
    aws_s3_object.keys_json
  ]
}

# Create local files with the key material
resource "local_file" "private_key" {
  content  = tls_private_key.oidc.private_key_pem
  filename = "${path.module}/sa-signer.key"
}

resource "local_file" "public_key" {
  content  = tls_private_key.oidc.public_key_pem
  filename = "${path.module}/sa-signer.key.pub"
}

# Output the k3d cluster create command
locals {
  k3d_create_command = <<-EOT
    k3d cluster create k3d-irsa \
      -v ${abspath(path.module)}:/irsa \
      --k3s-arg "--kube-apiserver-arg=--service-account-key-file=/irsa/sa-signer.key.pub"@server:\* \
      --k3s-arg "--kube-apiserver-arg=--service-account-signing-key-file=/irsa/sa-signer.key"@server:\* \
      --k3s-arg "--kube-apiserver-arg=--api-audiences=kubernetes.svc.default"@server:\* \
      --k3s-arg "--kube-apiserver-arg=--service-account-issuer=https://${aws_s3_bucket.oidc.bucket_regional_domain_name}"@server:\*
  EOT
}
