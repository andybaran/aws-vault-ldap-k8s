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
    aws-ebs-csi-driver = {
      service_account_role_arn = aws_iam_role.ebs_csi_driver.arn
    }
  }

  eks_managed_node_groups = {
    nodes = {
      instance_types = ["${var.instance_type}"]
      min_size       = 1
      max_size       = 3
      desired_size   = 3
    }
  }
}

data "aws_eks_cluster_auth" "eks_cluster_auth" {
  name = module.eks.cluster_name
}

# IAM role for EBS CSI Driver
data "aws_iam_policy_document" "ebs_csi_driver_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi_driver" {
  name               = "${local.resources_prefix}-ebs-csi-driver"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_driver_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  role       = aws_iam_role.ebs_csi_driver.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}


