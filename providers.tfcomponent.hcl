required_providers {
  vault = {
    source = "hashicorp/vault"
    version = "5.6.0"
  }
  aws = {
    source = "hashicorp/aws"
    version = "6.27.0"
  }
  kubernetes = {
    source = "hashicorp/kubernetes"
    version = "3.0.1"
  }
  helm = {
    source = "hashicorp/helm"
    version = "3.1.1"

  }
    tls = {
      source = "hashicorp/tls"
      version = "~> 4.0.5"
    }
        random = {
      source = "hashicorp/random"
      version = "~> 3.6.0"
    }
  http = {
    source = "hashicorp/http"
    version = "~> 3.5.0"
  }
}

variable "access_key" {
  description = "AWS access key"
  type        = string
  ephemeral   = true
}

variable "secret_key" {
  description = "AWS sensitive secret key."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "session_token" {
  description = "AWS session token."
  type        = string
  sensitive   = true
  ephemeral   = true
}

provider "aws" "this" {
  config {
  # shared_config_files = [var.tfc_aws_dynamic_credentials.default.shared_config_file]
  region = var.region
  access_key = var.access_key
  secret_key = var.secret_key
  token      = var.session_token

  #   default_tags {
  #     tags = {
  #       Demo    = "vault-secrets-operator"
  #       Company = local.customer_name
  #       BU      = "DDR"
  #       Env     = "dev"
  #     }
  #   }
  }
}

provider "vault" "this" {
  config {
    # skip_child_token = true
    # address          = var.tfc_vault_dynamic_credentials.default.address
    namespace = "admin/${var.customer_name}"

    # auth_login_token_file {
    #   filename = var.tfc_vault_dynamic_credentials.default.token_filename
    # }
  }
}



provider "helm" "this" {
/*   config {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
      command     = "aws"
    }
  }
  } */
}

provider "kubernetes" "this" {
/*   config {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    command     = "aws"
  }
  } */
}

provider "tls" "this" {
}

provider "random" "this" {
}

provider "http" "this" {
}