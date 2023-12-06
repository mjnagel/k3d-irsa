# IRSA on k3d

This is a guide on how to setup IRSA on k3d. It is primarily based on the [guide from AWS](https://github.com/aws/amazon-eks-pod-identity-webhook/blob/master/SELF_HOSTED_SETUP.md) with adaptations for k3d and the latest k8s versions.

## Generate the keypair

```console
export PRIV_KEY="sa-signer.key"
export PUB_KEY="sa-signer.key.pub"
export PKCS_KEY="sa-signer-pkcs8.pub"
ssh-keygen -t rsa -b 2048 -f $PRIV_KEY -m pem
ssh-keygen -e -m PKCS8 -f $PUB_KEY > $PKCS_KEY
```

## Make S3 Bucket

Note: Make sure to modify the command below to set `S3_BUCKET` to a unique name:

```console
export S3_BUCKET=<your-unique-name-here>
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
```

```console
go run ./main.go -key $PKCS_KEY  | jq '.keys += [.keys[0]] | .keys[1].kid = ""' > keys.json
```

Then copy these documents to your S3 bucket:

```console
aws s3 cp --acl public-read ./discovery.json s3://$S3_BUCKET/.well-known/openid-configuration
aws s3 cp --acl public-read ./keys.json s3://$S3_BUCKET/keys.json
```

## Configure OIDC provider in AWS IAM

Follow the guide [here](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html) using the below values:
- Provider: `https://$ISSUER_HOSTPATH` (fill in with actual value)
- Audience: `irsa`

## Create your k3d cluster

Note that the volume mount requires that this be run from this repo, or modify the command as necessary:

```console
k3d cluster create -v $(pwd):/irsa \
  --k3s-arg "--kube-apiserver-arg=--service-account-key-file=/irsa/${PKCS_KEY}"@server:\* \
  --k3s-arg "--kube-apiserver-arg=--service-account-signing-key-file=/irsa/${PRIV_KEY}"@server:\* \
  --k3s-arg "--kube-apiserver-arg=--api-audiences=kubernetes.svc.default"@server:\* \
  --k3s-arg "--kube-apiserver-arg=--service-account-issuer=https://${ISSUER_HOSTPATH}"@server:\*
```

## Apply the pod identity webhook

```console
# Create namespace and cert job
kubectl apply -f deploy/namespace.yaml
kubectl apply -f deploy/create-job.yaml
# Sleep for secret creation
sleep 10
# Deploy webhook resources
kubectl apply -f deploy/auth.yaml
kubectl apply -f deploy/deployment-base.yaml
kubectl apply -f deploy/mutatingwebhook.yaml
kubectl apply -f deploy/service.yaml
# Sleep for webhook to be created
sleep 10
# Create webhook cert patch job
kubectl apply -f deploy/patch-job.yaml
```

## Create an IAM role and annotate a service account to use IRSA

From this point everything should be configured and now the flow looks like this:
- Create an IAM Policy (for example: allow access to get objects from your bucket)
- Create an IAM Role associated with your service account
- Create a service account and pod with the `irsa/role-arn` annotation to assume

For a more in depth demo see the [demo walkthrough](./WALKTHROUGH.md) which will step you through creating a pod to access an S3 bucket.
