module "vpc" {
  source             = "terraform-aws-modules/vpc/aws"
  version            = "6.5.1"
  name               = "${local.resources_prefix}-vpc"
  cidr               = local.vpc_cidr
  azs                = local.azs
  enable_nat_gateway = true
  single_nat_gateway = true
  private_subnets    = [for idx, az in local.azs : cidrsubnet(local.vpc_cidr, 4, idx)]
  public_subnets     = [for idx, az in local.azs : cidrsubnet(local.vpc_cidr, 8, idx + 48)]

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}
