# Demo

This demo assumes you have already done the setup from the main [README](./README.md) and have setup the env variables created by that demo.

## Add a private file to our bucket

Let's add a txt file to our existing bucket that our pod should read:
```console
echo "Hello world" >> demo.txt
aws s3 cp --acl private ./demo.txt s3://$S3_BUCKET/demo.txt
```

Let's validate this artifact is private:
```console
curl https://$ISSUER_HOSTPATH/demo.txt
# Expect `Access Denied` message
```

## Make an IAM Policy

The below is a simple IAM policy that gives full read permission to our bucket:
```console
export policy_name=$S3_BUCKET-policy

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

aws iam create-policy --policy-name $policy_name --policy-document file://demo-policy.json
```

## Make an IAM Role

Now we need an IAM role that has a trust relationship with our service account:
```console
# Setup variables for our service account and OIDC provider
account_id=$(aws sts get-caller-identity --query "Account" --output text)
oidc_provider=$ISSUER_HOSTPATH
export namespace=default
export service_account=demo-sa
export role_name=$S3_BUCKET-role

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

aws iam create-role --role-name ${role_name} --assume-role-policy-document file://demo-trust-relationship.json --description "demo-irsa-role"
aws iam attach-role-policy --role-name ${role_name} --policy-arn=arn:aws:iam::${account_id}:policy/${policy_name}
```

## Deploy our pod

Now we can deploy a service account and pod that use this role:
```console
kubectl create serviceaccount -n ${namespace} ${service_account}
kubectl annotate serviceaccount -n ${namespace} ${service_account} irsa/role-arn=arn:aws:iam::${account_id}:role/${role_name}

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

Now let's validate we can pull the demo file from our bucket:
```console
kubectl exec -it aws-cli-pod -- env FILE=s3://$S3_BUCKET/demo.txt bash

# Inside the pod shell
aws s3 cp $FILE .
cat demo.txt
```

If all went well you should see `Hello world` since the file was copied!

## Cleanup

To clean up all your demo resources:

```console
kubectl delete po aws-cli-pod --force
kubectl delete sa $service_account
aws iam detach-role-policy --role-name ${role_name} --policy-arn=arn:aws:iam::${account_id}:policy/${policy_name}
aws iam delete-role --role-name ${role_name}
aws iam delete-policy --policy-arn=arn:aws:iam::${account_id}:policy/${policy_name}
aws s3 rm s3://$S3_BUCKET/demo.txt
rm -rf demo-policy.json demo.txt demo-trust-relationship.json
```
