# IRSA on k3d

This is a guide on how to setup IRSA on a local k3d cluster. The goal of this guide is to provide authentication between a local dev cluster and remote AWS resources (S3, etc). It is primarily based on the [guide from AWS](https://github.com/aws/amazon-eks-pod-identity-webhook/blob/master/SELF_HOSTED_SETUP.md) with specific steps for k3d and streamlined for simplicity with aws-cli.

The only pre-requisites are to have k3d, aws-cli, and go installed locally, as well as local access to an AWS account with permissions to operate on IAM and S3 resources. For a seamless copy-paste experience it is also helpful to run `export AWS_PAGER=""` which will ensure that the aws-cli will not open an interactive pager after resource creation.

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

Validate that the webhook pod is running and cert jobs completed successfully:
```console
kubectl get po -n irsa
```

## Create an IAM role and annotate a service account to use IRSA

From this point everything should be configured you can follow typical IRSA flows:
- Create an IAM Policy (for example: allow access to get objects from your bucket)
- Create an IAM Role associated with your service account
- Create a service account and pod with the `irsa/role-arn` annotation to assume 

Note that the annotation is intentionally different from the standard EKS annotation, and could be set to anything by modifying the `annotation-prefix` to something different in `deploy/deployment-base.yaml`. 

For a more in depth demo see the [demo walkthrough](./WALKTHROUGH.md) which will go through the above steps with examples to give a pod access to an S3 bucket.

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

Don't forget to also clean up the pieces from the [walkthrough](./WALKTHROUGH.md#Cleanup) if you created those.
