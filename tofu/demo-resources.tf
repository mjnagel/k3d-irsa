# Demo resources for testing IRSA
# These resources are conditionally created based on the deploy_demo_resources variable

# Create an IAM policy for S3 access
data "aws_partition" "current" {}

resource "aws_iam_policy" "demo_s3_access" {
  count       = var.deploy_demo_resources ? 1 : 0
  name        = "${var.bucket_name}-s3-access"
  description = "Policy that allows read access to the demo S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:${data.aws_partition.current.partition}:s3:::${var.bucket_name}",
          "arn:${data.aws_partition.current.partition}:s3:::${var.bucket_name}/*"
        ]
      }
    ]
  })
}

# Assume role policy for the service account
data "aws_iam_policy_document" "demo_assume_role" {
  count = var.deploy_demo_resources ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.oidc.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.oidc.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:default:demo-sa"]
    }
  }
}

# Create the IAM role
resource "aws_iam_role" "demo" {
  count                = var.deploy_demo_resources ? 1 : 0
  name                 = "${var.bucket_name}-demo-role"
  assume_role_policy   = data.aws_iam_policy_document.demo_assume_role[0].json
  permissions_boundary = var.permissions_boundary_arn
  tags = {
    PermissionsBoundary = split("/", var.permissions_boundary_arn)[1]
  }
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "demo_s3_access" {
  count      = var.deploy_demo_resources ? 1 : 0
  role       = aws_iam_role.demo[0].name
  policy_arn = aws_iam_policy.demo_s3_access[0].arn
}
