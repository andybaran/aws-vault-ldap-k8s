data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

locals {
  user_only          = replace(replace(var.user_email, "@hashicorp.com", "_test"), "@ibm.com", "_test")
  extra_doormat_role = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws_${local.user_only}-developer"
  partition          = data.aws_partition.current.partition
}

module "eks" {
  source                                   = "terraform-aws-modules/eks/aws"
  version                                  = "21.11.0"
  name                                     = "${local.resources_prefix}-eks"
  kubernetes_version                       = "1.34"
  endpoint_public_access                   = true
  enable_cluster_creator_admin_permissions = true
  vpc_id                                   = module.vpc.vpc_id
  subnet_ids                               = module.vpc.private_subnets
  # access_entries = {
  #   example = {
  #     kubernetes_groups = []
  #     principal_arn     = local.extra_doormat_role

  #     policy_associations = {
  #       admin = {
  #         policy_arn = "arn:${local.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  #         access_scope = {
  #           type = "cluster"
  #         }
  #       }
  #     }
  #   }
  # }
  kms_key_administrators = [
    local.extra_doormat_role,
    data.aws_iam_session_context.current.issuer_arn,
  ]
  addons = {
    coredns = {
      before_compute = true
    }
    eks-pod-identity-agent = {
      before_compute = true
    }
    kube-proxy = {
      before_compute = true
    }
    vpc-cni = {
      before_compute = true
    }
  }

  eks_managed_node_groups = {
    nodes = {
      instance_types = ["${var.instance_type}"]
      min_size       = 1
      max_size       = 3
      desired_size   = 1
    }
  }
}

data "aws_eks_cluster_auth" "eks_cluster_auth" {
  name = module.eks.cluster_id
}


