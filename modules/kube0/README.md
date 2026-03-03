# Module: kube0 — VPC, EKS Cluster, Security Groups

Provisions the foundational AWS networking and Kubernetes infrastructure for the demo. This is the first component in the Terraform Stack dependency chain — all other components depend on its outputs.

## Resources

| Resource | Description |
|----------|-------------|
| VPC (`terraform-aws-modules/vpc/aws` v6.5.1) | 10.0.0.0/16 CIDR, public + private subnets across up to 3 AZs, single NAT gateway |
| EKS Cluster (`terraform-aws-modules/eks/aws` v21.11.0) | Kubernetes 1.34, public endpoint, cluster creator granted admin permissions |
| EKS Managed Node Group (`linux_nodes`) | 1–3 nodes (desired: 3), `c5.xlarge` default, configurable AMI release version |
| EBS CSI Driver IAM Role | IRSA-backed role for the `aws-ebs-csi-driver` addon |
| Security Group (`shared_internal`) | Allows all inbound from VPC CIDR; used for inter-component communication |

## EKS Addons

Installed before compute nodes are ready (`before_compute = true`):

- `coredns`
- `eks-pod-identity-agent`
- `kube-proxy`
- `vpc-cni`
- `aws-ebs-csi-driver` (with IRSA role for EBS volume management)

## Input Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `region` | string | `"us-east-2"` | AWS region for this deployment |
| `user_email` | string | `"user@ibm.com"` | Operator e-mail; used to build IRSA ARNs |
| `instance_type` | string | `"t3.medium"` | EKS worker node instance type |
| `customer_name` | string | _(required)_ | Customer name; truncated to 4 chars for resource naming |
| `eks_node_ami_release_version` | string | `"1.34.2-20260128"` | EKS managed node group AMI release version |

## Outputs

| Output | Description |
|--------|-------------|
| `vpc_id` | VPC ID |
| `demo_id` | Short unique demo identifier (used in resource names) |
| `cluster_endpoint` | EKS API server endpoint |
| `kube_cluster_certificate_authority_data` | Base64-encoded cluster CA certificate |
| `eks_cluster_name` | Ready-to-run `aws eks update-kubeconfig` command |
| `eks_cluster_id` | EKS cluster ID |
| `eks_cluster_auth` | *(sensitive)* Short-lived authentication token for the cluster |
| `first_private_subnet_id` | First private subnet ID (used by Vault, EKS workloads) |
| `first_public_subnet_id` | First public subnet ID (used by the DC EC2 instance) |
| `shared_internal_sg_id` | Security group ID for intra-VPC communication |
| `resources_prefix` | Naming prefix applied to all resources in this deployment |

## Naming Convention

Resources are named using `local.resources_prefix`, which is derived from `customer_name` (first 4 characters) and a short random identifier. Example: `fide-a3k2`.

## Notes

- AZ selection filters to only AZs that support the requested instance type and picks up to 3.
- `enable_cluster_creator_admin_permissions = true` grants the deploying IAM role admin access to the cluster without a separate access entry.
