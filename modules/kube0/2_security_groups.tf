resource "aws_security_group" "shared_internal" {
  name        = "${local.resources_prefix}-shared-internal"
  description = "Shared security group for internal VPC communication (demo - allows all VPC traffic)"
  vpc_id      = module.vpc.vpc_id

  # Allow all traffic from within the VPC (EKS pods, nodes, admin VM, DC)
  ingress {
    description = "All traffic from VPC CIDR"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [local.vpc_cidr]
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
