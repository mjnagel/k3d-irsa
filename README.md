# IRSA on k3d

This repository provides resources for setting up IRSA (IAM Roles for Service Accounts) on a local k3d cluster. IRSA enables you to map AWS IAM roles to Kubernetes service accounts, allowing specific pods to securely access AWS resources. While IRSA is provided out of the box with AWS EKS clusters, it is also possible to self-host the IRSA setup on any cluster. This repository focuses specifically on how to do this for k3d clusters, although the steps can be easily adapted to k3s and RKE2 or other Kubernetes distributions.

## Setup Guides

Choose your preferred setup method:

1. **OpenTofu** - Automated setup using Infrastructure as Code:
   - [OpenTofu Setup](./docs/opentofu-setup.md)

2. **AWS CLI** - Step-by-step manual setup:
   - [CLI Setup](./docs/cli-setup.md)

## Key Steps

- Set up OIDC provider in AWS IAM
- Configure k3d with OIDC support
- Deploy the IRSA webhook for automatic credential injection
- Validate by setting up an IAM role and testing usage with a pod/service account

## Prerequisites

Each individual setup guide has some specific prerequisites, but these are required regardless of approach:

- **Kubernetes Tools**:
  - [k3d](https://k3d.io/stable/)
  - [kubectl](https://kubernetes.io/docs/reference/kubectl/)
  - [Helm](https://helm.sh/)
- **AWS Tools**:
  - [AWS CLI](https://aws.amazon.com/cli/)
  - AWS Account with appropriate IAM permissions

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.
