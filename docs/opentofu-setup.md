# OpenTofu Setup for IRSA on k3d

This guide provides a streamlined way to set up IRSA (IAM Roles for Service Accounts) on a local k3d cluster using OpenTofu.

> [!NOTE]
> If you prefer a more manual approach using AWS CLI, see the [CLI Setup](./cli-setup.md).

## Prerequisites

- **[OpenTofu](https://opentofu.org/)**: `>= 1.8.0`
- **[k3d](https://k3d.io/stable/)**: For creating and managing local Kubernetes clusters
- **[kubectl](https://kubernetes.io/docs/reference/kubectl/)**: For interacting with the Kubernetes cluster
- **[Helm](https://helm.sh/)**: For deploying the IRSA webhook
- **[aws-cli](https://aws.amazon.com/cli/)**: For AWS authentication
- **AWS Account**: With permissions to create IAM and S3 resources

## Setup Instructions

1. **Configure AWS Credentials**
   Ensure your AWS credentials are configured with appropriate permissions:
   ```bash
   aws configure
   ```

1. **Initialize OpenTofu**
   ```bash
   cd tofu
   tofu init # this will use a local backend by default for the demo
   ```

1. **Apply the Configuration**
   ```bash
   tofu apply -var="bucket_name=<your-unique-bucket-name>" -var="aws_region=<your-aws-region>"
   # Confirm with 'yes' when prompted
   ```
   Replace `<your-unique-bucket-name>` with a globally unique S3 bucket name and replace `<your-aws-region>` with the desired region.

1. **Create the k3d Cluster**
   After the OpenTofu apply completes, it will output the command to create your k3d cluster. Run the command exactly as shown in the output.

1. **Deploy the IRSA Webhook**
   The output will also include the command to deploy the IRSA webhook using Helm. Note that this command will (1) assume you are running it from the tofu directory and (2) include your specific region which is required for the webhook to work.

## Next Steps

If you are already familiar with IAM Roles and IRSA, the only difference at this point is the annotation name needed for using a specific IAM Role. Use the `irsa/role-arn` annotation to specify the IAM role to be used:

```console
# Example: Annotate a service account with an IAM role
kubectl annotate serviceaccount -n default my-service-account \
  irsa/role-arn=arn:aws:iam::<account-id>:role/<role-name>
```

If you want to go through a more in depth tutorial, you can proceed to the [OpenTofu Usage Guide](./opentofu-usage.md) to learn how to:

- Create IAM roles and policies
- Configure service accounts to use those IAM roles

For more information, see the [AWS IRSA documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)

## Cleanup

To clean up all resources:

1. Delete the k3d cluster:
   ```bash
   k3d cluster delete k3d-irsa
   ```

2. Destroy OpenTofu resources:
   ```bash
   cd tofu
   tofu destroy -var="bucket_name=<your-unique-bucket-name>" -var="aws_region=<your-aws-region>"
   ```

> **Note**: If you followed the [OpenTofu Usage Guide](./opentofu-usage.md), make sure to pass in `-var="deploy_demo_resources=true"` on your destroy to also destroy those resources.
