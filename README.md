# IRSA on k3d

This is a guide on how to setup IRSA on k3d. It is primarily based on the [guide from AWS](https://github.com/aws/amazon-eks-pod-identity-webhook/blob/master/SELF_HOSTED_SETUP.md) with adaptations for k3d and the latest k8s versions.

The only pre-requisites are to have k3d and aws-cli installed locally, as well as local access to an AWS account with permissions to operate on IAM and S3 resources. For a seamless copy-paste experience it is also helpful to run `export AWS_PAGER=""` which will ensure that the aws-cli will not open an interactive pager after resource creation.

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

Note: By default the below commands set `S3_BUCKET` to part of your AWS username + a suffix with a few random characters and `-irsa`. You may want to change this to something you can remember easily, the default is for easy use when copy-pasting.

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

go run ./main.go -key $PKCS_KEY  | jq '.keys += [.keys[0]] | .keys[1].kid = ""' > keys.json
```

Then copy these documents to your S3 bucket:

```console
aws s3 cp --acl public-read ./discovery.json s3://$S3_BUCKET/.well-known/openid-configuration
aws s3 cp --acl public-read ./keys.json s3://$S3_BUCKET/keys.json
```

## Configure OIDC provider in AWS IAM

Note that since we are using S3 the thumbprint list is not important, but required by the AWS CLI. In a real environment with a different provider you could follow [this guide](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc_verify-thumbprint.html) to find the thumbprint.

```console
aws iam create-open-id-connect-provider --url https://$ISSUER_HOSTPATH --client-id-list irsa --thumbprint-list demodemodemodemodemodemodemodemodemodemo
```

## Create your k3d cluster

Note that the volume mount requires that this be run from this repo, or modify the command as necessary:

```console
k3d cluster create -v $(pwd):/irsa \
  --k3s-arg "--kube-apiserver-arg=--service-account-key-file=/irsa/${PKCS_KEY}"@server:\* \
  --k3s-arg "--kube-apiserver-arg=--service-account-signing-key-file=/irsa/${PRIV_KEY}"@server:\* \
  --k3s-arg "--kube-apiserver-arg=--api-audiences=kubernetes.svc.default"@server:\* \
  --k3s-arg "--kube-apiserver-arg=--service-account-issuer=https://${ISSUER_HOSTPATH}"@server:\*
```

Wait until the cluster default resources (networking, etc) are healthy before proceeding.

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

Validate that the webhook pod is running and bot jobs completed successfully:
```console
kubectl get po -n irsa
```

## Create an IAM role and annotate a service account to use IRSA

From this point everything should be configured and now the flow looks like this:
- Create an IAM Policy (for example: allow access to get objects from your bucket)
- Create an IAM Role associated with your service account
- Create a service account and pod with the `irsa/role-arn` annotation to assume

For a more in depth demo see the [demo walkthrough](./WALKTHROUGH.md) which will step you through creating a pod to access an S3 bucket.

## Cleanup

If you were just doing this for a demo you can clean up all the pieces you created by doing the following:
```console
k3d cluster delete
account_id=$(aws sts get-caller-identity --query "Account" --output text)
aws iam delete-open-id-connect-provider --open-id-connect-provider-arn arn:aws:iam::${account_id}:oidc-provider/${ISSUER_HOSTPATH}
aws s3 rm s3://$S3_BUCKET --recursive
aws s3api delete-bucket --bucket $S3_BUCKET
# Cleanup local files
rm -rf $PRIV_KEY $PUB_KEY $PKCS_KEY discovery.json keys.json
```
