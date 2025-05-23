# IRSA Helm Chart

This Helm chart deploys the IAM Roles for Service Accounts (IRSA) webhook for Kubernetes clusters. It enables pods to assume AWS IAM roles through service account annotations.

## Overview

This chart deploys the Amazon EKS Pod Identity Webhook, which allows Kubernetes service accounts to assume AWS IAM roles. This implementation is designed for use with k3d or other Kubernetes distributions where EKS IRSA is not natively available.

## Prerequisites

- Kubernetes 1.16+
- Helm 3.0+
- AWS account with appropriate permissions
- OIDC provider configured in AWS IAM

## Installation

```bash
# Install the chart (will create the namespace if it doesn't exist)
helm install irsa ./chart -n irsa --create-namespace
```

## Configuration

The following table lists the configurable parameters of the IRSA chart and their default values.

| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `podIdentityWebhook.image.repository` | Pod identity webhook image repository | `amazon/amazon-eks-pod-identity-webhook` |
| `podIdentityWebhook.image.tag` | Pod identity webhook image tag | `v0.6.7` |
| `podIdentityWebhook.image.pullPolicy` | Pod identity webhook image pull policy | `Always` |
| `podIdentityWebhook.config.annotationPrefix` | Annotation prefix for service accounts | `irsa` |
| `podIdentityWebhook.config.tokenAudience` | Token audience for OIDC | `irsa` |
| `podIdentityWebhook.config.namespace` | Namespace for the webhook | `kube-system` |
| `podIdentityWebhook.config.serviceName` | Service name for the webhook | `pod-identity-webhook` |
| `podIdentityWebhook.config.stsRegionalEndpoint` | Use regional STS endpoints | `true` |
| `podIdentityWebhook.config.region` | AWS region for STS endpoint | `us-east-1` |
| `webhookCert.image.repository` | Certificate generator/patcher image repository | `k8s.gcr.io/ingress-nginx/kube-webhook-certgen` |
| `webhookCert.image.tag` | Certificate generator/patcher image tag | `v1.5.3` |
| `webhookCert.config.secretName` | Certificate secret name | `pod-identity-webhook-cert` |
| `rbac.create` | Create RBAC resources | `true` |

## Usage

After installing the chart, you can annotate service accounts with the IAM role ARN:

```bash
kubectl annotate serviceaccount -n default my-service-account irsa/role-arn=arn:aws:iam::123456789012:role/my-role
```

The annotation prefix (`irsa` by default) can be customized through the `podIdentityWebhook.config.annotationPrefix` value.

## Uninstallation

```bash
helm uninstall irsa
```

## Notes

- This chart uses Helm hooks to properly sequence the creation of resources and certificate generation
- The webhook patch job runs after installation to configure the webhook with the generated certificates
