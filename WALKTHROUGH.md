# IRSA Demo Walkthrough

## Overview

This walkthrough demonstrates how to use IRSA to give a Kubernetes pod access to an S3 bucket. It assumes you have already:

1. Completed the setup from the main [README](./README.md)
2. Set up the environment variables created during that process

## Step 1: Add a Private File to S3

First, let's create a test file and upload it to our S3 bucket with private access control:

```console
# Create a simple text file
echo "Hello world" > demo.txt

# Upload it to S3 with private ACL
aws s3 cp --acl private ./demo.txt s3://$S3_BUCKET/demo.txt
```

Verify that the file is indeed private by attempting to access it directly:

```console
# This should return an Access Denied error
curl https://$ISSUER_HOSTPATH/demo.txt
```

## Step 2: Create an IAM Policy

Next, we'll create an IAM policy that grants read access to our S3 bucket:

```console
# Set the policy name based on our bucket name
export policy_name=$S3_BUCKET-policy

# Create the policy JSON document
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
        "arn:aws:s3:::${S3_BUCKET}/*",
        "arn:aws:s3:::${S3_BUCKET}"
      ]
    }
  ]
}
EOF

# Create the IAM policy in AWS
aws iam create-policy --policy-name $policy_name --policy-document file://demo-policy.json
```

## Step 3: Create an IAM Role with Trust Relationship

Now we'll create an IAM role that can be assumed by our Kubernetes service account through the OIDC provider:

```console
# Setup variables for our service account and OIDC provider
account_id=$(aws sts get-caller-identity --query "Account" --output text)
oidc_provider=$ISSUER_HOSTPATH
export namespace=default
export service_account=demo-sa
export role_name=$S3_BUCKET-role

# Create the trust relationship JSON document
cat >demo-trust-relationship.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${account_id}:oidc-provider/${oidc_provider}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${oidc_provider}:aud": "irsa",
          "${oidc_provider}:sub": "system:serviceaccount:${namespace}:${service_account}"
        }
      }
    }
  ]
}
EOF

# Create the IAM role with the trust relationship
aws iam create-role --role-name ${role_name} \
  --assume-role-policy-document file://demo-trust-relationship.json \
  --description "demo-irsa-role"

# Attach the S3 access policy to the role
aws iam attach-role-policy --role-name ${role_name} \
  --policy-arn=arn:aws:iam::${account_id}:policy/${policy_name}
```

## Step 4: Deploy a Pod with IRSA

Now we'll create a Kubernetes service account, annotate it with our IAM role, and deploy a pod that uses this service account:

```console
# Create a service account
kubectl create serviceaccount -n ${namespace} ${service_account}

# Annotate the service account with the IAM role ARN
kubectl annotate serviceaccount -n ${namespace} ${service_account} \
  irsa/role-arn=arn:aws:iam::${account_id}:role/${role_name}

# Deploy a pod that uses this service account
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: aws-cli-pod
  namespace: default
spec:
  serviceAccountName: $service_account
  containers:
  - name: aws-cli-container
    image: amazon/aws-cli
    command: ["/bin/sh", "-c", "while true; do sleep 30; done"]
EOF
```

## Step 5: Verify AWS Access

Wait until the pod is running, then validate that it can access the S3 bucket using the assumed IAM role:

```console
# Execute a shell in the pod with our S3 file path set as an environment variable
kubectl exec -it aws-cli-pod -- env FILE=s3://$S3_BUCKET/demo.txt bash

# Inside the pod shell, try to download the file from S3
aws s3 cp $FILE .
cat demo.txt
```

If IRSA is working correctly, you should see `Hello world` displayed, confirming that the pod was able to download the private file from S3 using the IAM role credentials!

## Cleanup

When you're done with the demo, follow these steps to clean up the resources:

```console
# Remove the Kubernetes resources
kubectl delete pod aws-cli-pod --force
kubectl delete serviceaccount $service_account -n ${namespace}

# Remove the IAM role and policy
aws iam detach-role-policy \
  --role-name ${role_name} \
  --policy-arn=arn:aws:iam::${account_id}:policy/${policy_name}
aws iam delete-role --role-name ${role_name}
aws iam delete-policy --policy-arn=arn:aws:iam::${account_id}:policy/${policy_name}

# Remove the S3 demo file
aws s3 rm s3://$S3_BUCKET/demo.txt

# Clean up local files
rm -rf demo-policy.json demo.txt demo-trust-relationship.json
```

> **Note**: For a complete cleanup, don't forget to also follow the [main cleanup steps](./README.md#Cleanup) from the README.
