resource "aws_security_group" "shared_internal" {
  name        = "${local.resources_prefix}-shared-internal"
  description = "Shared security group for internal communication between admin VM and domain controller"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "All traffic from members of this security group"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.resources_prefix}-shared-internal"
  }
}

# Security group rule to allow LDAP traffic from EKS cluster to LDAP server
# This enables the create-ad-user job running in EKS to connect to the DC
resource "aws_security_group_rule" "ldap_from_eks" {
  description              = "Allow LDAP traffic from EKS cluster nodes"
  type                     = "ingress"
  from_port                = 389
  to_port                  = 389
  protocol                 = "tcp"
  source_security_group_id = module.eks.node_security_group_id
  security_group_id        = aws_security_group.shared_internal.id
}

# Allow LDAPS (secure LDAP) as well in case it's needed
resource "aws_security_group_rule" "ldaps_from_eks" {
  description              = "Allow LDAPS traffic from EKS cluster nodes"
  type                     = "ingress"
  from_port                = 636
  to_port                  = 636
  protocol                 = "tcp"
  source_security_group_id = module.eks.node_security_group_id
  security_group_id        = aws_security_group.shared_internal.id
}

# Allow Kerberos from EKS (may be needed for AD authentication)
resource "aws_security_group_rule" "kerberos_tcp_from_eks" {
  description              = "Allow Kerberos TCP traffic from EKS cluster nodes"
  type                     = "ingress"
  from_port                = 88
  to_port                  = 88
  protocol                 = "tcp"
  source_security_group_id = module.eks.node_security_group_id
  security_group_id        = aws_security_group.shared_internal.id
}

resource "aws_security_group_rule" "kerberos_udp_from_eks" {
  description              = "Allow Kerberos UDP traffic from EKS cluster nodes"
  type                     = "ingress"
  from_port                = 88
  to_port                  = 88
  protocol                 = "udp"
  source_security_group_id = module.eks.node_security_group_id
  security_group_id        = aws_security_group.shared_internal.id
}

# Allow DNS from EKS to DC (AD DNS)
resource "aws_security_group_rule" "dns_tcp_from_eks" {
  description              = "Allow DNS TCP traffic from EKS cluster nodes"
  type                     = "ingress"
  from_port                = 53
  to_port                  = 53
  protocol                 = "tcp"
  source_security_group_id = module.eks.node_security_group_id
  security_group_id        = aws_security_group.shared_internal.id
}

resource "aws_security_group_rule" "dns_udp_from_eks" {
  description              = "Allow DNS UDP traffic from EKS cluster nodes"
  type                     = "ingress"
  from_port                = 53
  to_port                  = 53
  protocol                 = "udp"
  source_security_group_id = module.eks.node_security_group_id
  security_group_id        = aws_security_group.shared_internal.id
}
