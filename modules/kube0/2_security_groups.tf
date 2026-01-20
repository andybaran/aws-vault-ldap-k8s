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
