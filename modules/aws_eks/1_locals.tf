locals {
  customer_name    = var.customer_name != "" ? substr(var.customer_name, 0, 4) : "hashicat-inc"
  customer_id      = "${random_string.identifier.result}-${local.customer_name}"
  demo_name        = "secrets-operator"
  demo_id          = "${local.customer_id}-${local.demo_name}"
  global_id        = lower(substr(base64encode(local.demo_id), 0, 6))
  resources_prefix = replace("${local.customer_name}-${local.global_id}", "-$", "") # make sure prefixes don't end with a hyphen
  vpc_cidr         = "10.0.0.0/16"
  database_name    = "demodb"
}

data "aws_availability_zones" "available" {
  filter {
    name   = "zone-type"
    values = ["availability-zone"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_ec2_instance_type_offerings" "supported" {
  location_type = "availability-zone"

  filter {
    name   = "instance-type"
    values = [var.instance_type]
  }
}

locals {
  candidate_azs = [
    for az in data.aws_availability_zones.available.names : az
    if contains(data.aws_ec2_instance_type_offerings.supported.locations, az)
  ]

  sorted_candidate_azs = sort(local.candidate_azs)

  azs = slice(
    local.sorted_candidate_azs,
    0,
    min(length(local.sorted_candidate_azs), 3)
  )
}

#------------------------------------------------------------------------------------
# Enable for debugging purposes
#------------------------------------------------------------------------------------

# resource "terraform_data" "availability_zones" {
#   input = {
#     availability_zones   = data.aws_availability_zones.available.names
#     offerings            = data.aws_ec2_instance_type_offerings.supported.locations
#     candidate_azs        = local.candidate_azs
#     sorted_candidate_azs = local.sorted_candidate_azs
#     azs                  = local.azs
#     timestamp            = timestamp()
#   }
# }

resource "random_string" "identifier" {
  length  = 4
  special = false
  numeric = false
  upper   = false
}
