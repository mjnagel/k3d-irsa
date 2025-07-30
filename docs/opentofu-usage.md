# Using IRSA with OpenTofu

This guide demonstrates how to use IRSA with AWS resources after setting up your k3d cluster using the [OpenTofu Setup](./opentofu-setup.md).

## Prerequisites

- Completed the [OpenTofu Setup](./opentofu-setup.md)
- `kubectl` configured to talk to your k3d cluster
- AWS CLI configured with appropriate permissions

## Deploying Demo Resources

1. Enable the demo resources by applying the configuration with the `deploy_demo_resources` variable set to `true`. If you're in an environment that requires a permissions boundary, include the `permissions_boundary_arn` variable:

  ```bash
  cd tofu

  # For basic environments:
  tofu apply \
    -var="bucket_name=<your-unique-bucket-name>" \
    -var="aws_region=<your-aws-region>" \
    -var="deploy_demo_resources=true"
  # Confirm with 'yes' when prompted

  # For environments requiring a permissions boundary:
  tofu apply \
    -var="bucket_name=<your-unique-bucket-name>" \
    -var="aws_region=<your-aws-region>" \
    -var="deploy_demo_resources=true" \
    -var="permissions_boundary_arn=<your-permissions-boundary-arn>"
  # Confirm with 'yes' when prompted
  ```
   
   Replace all bracketed values with the same values used on previous applies.

1. After the deployment completes, get the demo role ARN:

   ```bash
   tofu output demo_role_arn
   ```

## Creating a Kubernetes Service Account

1. Create the service account from the manifest:
   ```bash
   kubectl apply -f ../manifests/demo-serviceaccount.yaml
   ```

2. Add the IRSA annotation to the service account using the role ARN from the OpenTofu output:
   ```bash
   kubectl annotate serviceaccount demo-sa \
     --namespace default \
     irsa/role-arn=$(tofu output -raw demo_role_arn) --overwrite
   ```

## Testing the Setup

1. Create a test pod that uses the service account:
   ```bash
   kubectl apply -f ../manifests/test-pod.yaml
   ```

2. Verify the pod is running:
   ```bash
   kubectl get pod aws-cli
   ```

3. Test S3 access from the pod by creating and uploading a test file:
   ```bash
   # Create a test file
   echo "Hello, IRSA" > test-file.txt
   
   # Upload the test file to S3
   aws s3 cp test-file.txt s3://$(tofu output -raw s3_bucket_name)/
   
   # Verify the file was uploaded
   aws s3 ls s3://$(tofu output -raw s3_bucket_name)/
   
   # From inside the pod, verify the pod can read the file
   kubectl exec -it aws-cli -- aws s3 cp s3://$(tofu output -raw s3_bucket_name)/test-file.txt /tmp/
   kubectl exec -it aws-cli -- cat /tmp/test-file.txt
   
   # The pod should not be able to upload files (our policy only allows GetObject and ListBucket)
   kubectl exec -it aws-cli -- sh -c "echo 'This should fail' > /tmp/fail.txt && \
     aws s3 cp /tmp/fail.txt s3://$(tofu output -raw s3_bucket_name)/fail.txt || \
     echo 'Expected failure occurred (this is good)'"
   ```

## Cleanup

When you're done testing, clean up the resources:

```bash
# Delete the test pod and service account
kubectl delete -f ../manifests/test-pod.yaml
kubectl delete -f ../manifests/demo-serviceaccount.yaml

# Clean up test files
rm -f test-file.txt

# Clean up the OpenTofu resources (including demo resources)
tofu destroy -var="bucket_name=<your-unique-bucket-name>" -var="aws_region=<your-aws-region>" -var="deploy_demo_resources=true"
# Confirm with 'yes' when prompted
```

> **Note**: If you want to keep the IRSA infrastructure but remove just the demo resources, you can run:
> ```bash
> tofu apply -var="bucket_name=<your-unique-bucket-name>" -var="aws_region=<your-aws-region>" -var="deploy_demo_resources=false"
> ```
