# IRSA on k3d

This is a guide on how to setup IRSA (IAM Roles for Service Accounts) on a local k3d cluster. The goal is to provide authentication between a local development cluster and remote AWS resources (S3, etc). It is primarily based on the [guide from AWS](https://github.com/aws/amazon-eks-pod-identity-webhook/blob/master/SELF_HOSTED_SETUP.md) with specific steps for k3d and streamlined for simplicity.

## Prerequisites

Before you begin, ensure you have the following installed:

- **[k3d](https://k3d.io/stable/)**: For creating and managing local Kubernetes clusters
- **[kubectl](https://kubernetes.io/docs/reference/kubectl/)**: For interacting with the Kubernetes cluster
- **[Helm](https://helm.sh/)**: For deploying the IRSA webhook
- **[aws-cli](https://aws.amazon.com/cli/)**: For AWS resource management
- **[go](https://go.dev/)**: For generating the OIDC keys
- **AWS Account**: With permissions to operate on IAM and S3 resources

> **Tip**: Run `export AWS_PAGER=""` to ensure the aws-cli doesn't open an interactive pager after resource creation.

## Generate the keypair

```console
export PRIV_KEY="sa-signer.key"
export PUB_KEY="sa-signer.key.pub"
export PKCS_KEY="sa-signer-pkcs8.pub"
# Skipping passphrase for the key
ssh-keygen -t rsa -b 2048 -f $PRIV_KEY -m pem -P ""
ssh-keygen -e -m PKCS8 -f $PUB_KEY > $PKCS_KEY
```

## Make S3 Bucket

Note: By default the below commands set `S3_BUCKET` to part of your AWS username + a suffix with a few random characters and `-irsa`. You may want to change this to something you can remember easily, the default is for easy use when copy-pasting from this guide.

```console
export S3_BUCKET=$(aws sts get-caller-identity --query Arn --output text | cut -f 2 -d '/' | awk -F'.' '{print $1}')-$(openssl rand -base64 20 | tr -dc 'a-z' | head -c 3)-irsa
_bucket_name=$(aws s3api list-buckets  --query "Buckets[?Name=='$S3_BUCKET'].Name | [0]" --out text)
if [ $_bucket_name = "None" ]; then
  aws s3api create-bucket --bucket $S3_BUCKET --create-bucket-configuration LocationConstraint=$AWS_REGION --object-ownership=BucketOwnerPreferred
fi
aws s3api delete-public-access-block --bucket $S3_BUCKET
export HOSTNAME=s3.$AWS_REGION.amazonaws.com
export ISSUER_HOSTPATH=$HOSTNAME/$S3_BUCKET
```

## Create OIDC documents

```console
cat <<EOF > discovery.json
{
    "issuer": "https://$ISSUER_HOSTPATH",
    "jwks_uri": "https://$ISSUER_HOSTPATH/keys.json",
    "authorization_endpoint": "urn:kubernetes:programmatic_authorization",
    "response_types_supported": [
        "id_token"
    ],
    "subject_types_supported": [
        "public"
    ],
    "id_token_signing_alg_values_supported": [
        "RS256"
    ],
    "claims_supported": [
        "sub",
        "iss"
    ]
}
EOF

go run ./main.go -key $PKCS_KEY > keys.json
```

Then copy these documents to your S3 bucket:

```console
aws s3 cp --acl public-read ./discovery.json s3://$S3_BUCKET/.well-known/openid-configuration
aws s3 cp --acl public-read ./keys.json s3://$S3_BUCKET/keys.json
```

## Configure OIDC provider in AWS IAM

Note that since we are using S3 for our OIDC provider, the thumbprint list is not important but is required by the AWS CLI. In a production environment with a different provider you could follow [this guide](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc_verify-thumbprint.html) to find the thumbprint.

```console
aws iam create-open-id-connect-provider --url https://$ISSUER_HOSTPATH --client-id-list irsa --thumbprint-list demodemodemodemodemodemodemodemodemodemo
```

## Create your k3d cluster

Note that the volume mount requires that this be run from this repo, or modify the command as necessary to volume mount from a different location.

```console
k3d cluster create -v $(pwd):/irsa \
  --k3s-arg "--kube-apiserver-arg=--service-account-key-file=/irsa/${PKCS_KEY}"@server:\* \
  --k3s-arg "--kube-apiserver-arg=--service-account-signing-key-file=/irsa/${PRIV_KEY}"@server:\* \
  --k3s-arg "--kube-apiserver-arg=--api-audiences=kubernetes.svc.default"@server:\* \
  --k3s-arg "--kube-apiserver-arg=--service-account-issuer=https://${ISSUER_HOSTPATH}"@server:\*
```

Wait until the cluster default resources (networking, etc) are healthy before proceeding.

## Deploy the pod identity webhook

The pod identity webhook is deployed using Helm, which provides proper resource orchestration and configuration options:

```console
# Install using Helm (will create the namespace if it doesn't exist)
helm upgrade -i irsa ./charts/irsa -n irsa --create-namespace --wait
```

### Configuration Options

The Helm chart provides several configuration options through `values.yaml`:

| Option | Description | Default |
|--------|-------------|--------|
| `podIdentityWebhook.config.annotationPrefix` | Annotation prefix for service accounts | `irsa` |
| `podIdentityWebhook.config.region` | AWS region for STS endpoints | `us-east-1` |
| `podIdentityWebhook.image.tag` | Pod identity webhook image version | `v0.6.7` |

See the chart's [README.md](./charts/irsa/README.md) for more details on available configuration options.

### Verify Deployment

Validate that the webhook pod is running and cert jobs completed successfully:

```console
kubectl get pods -n irsa
```

## Using IRSA with your applications

Once the webhook is deployed, you can follow these steps to use IRSA with your applications:

1. **Create an IAM Policy** - Define permissions for accessing AWS resources (e.g., S3 bucket access)
2. **Create an IAM Role** - Associate it with your Kubernetes service account
3. **Annotate your Service Account** - Use the `irsa/role-arn` annotation to specify the IAM role

```console
# Example: Annotate a service account with an IAM role
kubectl annotate serviceaccount -n default my-service-account \
  irsa/role-arn=arn:aws:iam::<account-id>:role/<role-name>
```

> **Note**: The annotation prefix (`irsa`) is intentionally different from the standard EKS annotation and can be customized by setting the `podIdentityWebhook.config.annotationPrefix` value in your Helm chart.

For a more in depth demo see the [demo walkthrough](./WALKTHROUGH.md) which will go through the above steps with examples to give a pod access to an S3 bucket.

## Cleanup

When you're done with the demo, you can clean up all resources with the following steps:

### 1. Remove the Helm chart

```console
helm uninstall irsa -n irsa
```

### 2. Delete the k3d cluster

```console
k3d cluster delete
```

### 3. Remove AWS resources

```console
# Get your AWS account ID
account_id=$(aws sts get-caller-identity --query "Account" --output text)

# Delete the OIDC provider
aws iam delete-open-id-connect-provider --open-id-connect-provider-arn \
  arn:aws:iam::${account_id}:oidc-provider/${ISSUER_HOSTPATH}

# Remove S3 bucket contents and the bucket itself
aws s3 rm s3://$S3_BUCKET --recursive
aws s3api delete-bucket --bucket $S3_BUCKET
```

### 4. Clean up local files

```console
rm -rf $PRIV_KEY $PUB_KEY $PKCS_KEY discovery.json keys.json
```

> **Note**: If you followed the [demo walkthrough](./WALKTHROUGH.md), don't forget to also clean up those resources by following the [walkthrough cleanup instructions](./WALKTHROUGH.md#Cleanup).
