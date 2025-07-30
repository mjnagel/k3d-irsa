# Using IRSA with CLI

This guide walks through using IRSA with AWS resources after setting up your k3d cluster using the [CLI Setup](./cli-setup.md).

## Prerequisites

- Completed the [CLI Setup](./cli-setup.md)
- `kubectl` configured to talk to your k3d cluster
- AWS CLI configured with appropriate permissions

## Creating an S3 Access Policy

Make sure that you still have any environment variables from the setup set on your current terminal. If you don't, make sure to `export S3_BUCKET=<name of your bucket>` at a minimum.

1. First, set up your environment variables:
   ```bash
   export policy_name=${S3_BUCKET}-policy
   export partition=$(aws sts get-caller-identity --query 'Arn' --output text | cut -d: -f2)
   ```

2. Create the policy JSON document:
   ```bash
   cat >demo-policy.json <<EOF
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "s3:GetObject",
           "s3:ListBucket"
         ],
         "Resource": [
           "arn:${partition}:s3:::${S3_BUCKET}/*",
           "arn:${partition}:s3:::${S3_BUCKET}"
         ]
       }
     ]
   }
   EOF
   ```

3. Create the IAM policy in AWS:
   ```bash
   aws iam create-policy --policy-name $policy_name --policy-document file://demo-policy.json
   ```

## Creating an IAM Role with Trust Relationship

1. Set up variables for your service account and OIDC provider:
   ```bash
   export account_id=$(aws sts get-caller-identity --query "Account" --output text)
   export ISSUER_HOSTPATH=s3.${AWS_REGION}.amazonaws.com/${S3_BUCKET}
   export namespace=default
   export service_account=demo-sa
   export role_name=${S3_BUCKET}-role
   ```

2. Create the trust relationship JSON document:
   ```bash
   cat >demo-trust-relationship.json <<EOF
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": {
           "Federated": "arn:aws:iam::${account_id}:oidc-provider/${ISSUER_HOSTPATH}"
         },
         "Action": "sts:AssumeRoleWithWebIdentity",
         "Condition": {
           "StringEquals": {
             "${ISSUER_HOSTPATH}:sub": "system:serviceaccount:${namespace}:${service_account}"
           }
         }
       }
     ]
   }
   EOF
   ```

3. Create the IAM role:
   ```bash
   aws iam create-role \
     --role-name $role_name \
     --assume-role-policy-document file://demo-trust-relationship.json \
     --description "IRSA demo role for S3 access"
   ```

   Note: If your environment has a permissions boundary you may need to include additional CLI args here, such as: 
   - `--permissions-boundary "<permissions-boundary-arn>"`
   - `--tags '{"Key": "PermissionsBoundary", "Value": "<permissions-boundary-name"}'`

4. Attach the policy to the role:
   ```bash
   policy_arn=$(aws iam list-policies --query "Policies[?PolicyName=='${policy_name}'].Arn" --output text)
   aws iam attach-role-policy \
     --role-name $role_name \
     --policy-arn $policy_arn
   ```

## Creating a Kubernetes Service Account

1. Create the service account from the manifest:
   ```bash
   kubectl apply -f ./manifests/demo-serviceaccount.yaml
   ```

2. Add the IRSA annotation to the service account:
   ```bash
   kubectl annotate serviceaccount demo-sa \
     --namespace default \
     irsa/role-arn=arn:${partition}:iam::${account_id}:role/${role_name} --overwrite
   ```

## Testing the Setup

1. Create a test pod that uses the service account:
   ```bash
   kubectl apply -f ./manifests/test-pod.yaml
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
   aws s3 cp test-file.txt s3://${S3_BUCKET}/
   
   # Verify the file was uploaded
   aws s3 ls s3://${S3_BUCKET}/
   
   # From inside the pod, verify the pod can read the file
   kubectl exec -it aws-cli -- aws s3 cp s3://${S3_BUCKET}/test-file.txt /tmp/
   kubectl exec -it aws-cli -- cat /tmp/test-file.txt
   
   # The pod should not be able to upload files (our policy only allows GetObject and ListBucket)
   kubectl exec -it aws-cli -- sh -c "echo 'This should fail' > /tmp/fail.txt && \
     aws s3 cp /tmp/fail.txt s3://${S3_BUCKET}/fail.txt || \
     echo 'Expected failure occurred (this is good)'"
   ```

## Cleanup

When you're done testing, clean up the resources:

```bash
# Delete the test pod and service account
kubectl delete -f ./manifests/test-pod.yaml
kubectl delete -f ./manifests/demo-serviceaccount.yaml

# Detach policy and delete the IAM role
aws iam detach-role-policy --role-name $role_name --policy-arn $policy_arn
aws iam delete-role --role-name $role_name

# Delete the IAM policy
aws iam delete-policy --policy-arn $policy_arn

# Clean up test files
rm -f test-file.txt

# Clean up local files (keep the manifests for future use)
rm -f demo-policy.json demo-trust-relationship.json
```

If you are cleaning up your environment completely, make sure to delete any resources from the setup by following those [cleanup instructions](./cli-setup.md#Cleanup).
