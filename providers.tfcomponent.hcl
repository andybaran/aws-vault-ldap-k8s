required_providers {
  aws = {
    source  = "hashicorp/aws"
    version = "6.27.0"
  }
  vault = {
    source  = "hashicorp/vault"
    version = "5.6.0"
  }
  kubernetes = {
    source  = "hashicorp/kubernetes"
    version = "3.0.1"
  }
  helm = {
    source  = "hashicorp/helm"
    version = "3.1.1"
  }
  tls = {
    source  = "hashicorp/tls"
    version = "~> 4.0.5"
  }
  random = {
    source  = "hashicorp/random"
    version = "~> 3.6.0"
  }
  http = {
    source  = "hashicorp/http"
    version = "~> 3.5.0"
  }
  cloudinit = {
    source  = "hashicorp/cloudinit"
    version = "2.3.7"
  }
  null = {
    source  = "hashicorp/null"
    version = "3.2.4"
  }
  time = {
    source  = "hashicorp/time"
    version = "0.13.1"
  }
}

provider "aws" "this" {
  config {
    # shared_config_files = [var.tfc_aws_dynamic_credentials.default.shared_config_file]
    region     = var.region
    access_key = var.AWS_ACCESS_KEY_ID
    secret_key = var.AWS_SECRET_ACCESS_KEY
    token      = var.AWS_SESSION_TOKEN

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
    address         = component.vault_cluster.vault_loadbalancer_hostname
    token           = component.vault_cluster.vault_root_token
    skip_tls_verify = true
  }
}



provider "helm" "this" {
  config {
    kubernetes = {
      host                   = component.kube0.cluster_endpoint
      cluster_ca_certificate = base64decode(component.kube0.kube_cluster_certificate_authority_data)
      token                  = component.kube0.eks_cluster_auth
    }
  }
}

provider "kubernetes" "this" {
  config {
    host                   = component.kube0.cluster_endpoint
    cluster_ca_certificate = base64decode(component.kube0.kube_cluster_certificate_authority_data)
    token                  = component.kube0.eks_cluster_auth
  }
}

provider "tls" "this" {
}

provider "random" "this" {
}

provider "http" "this" {
}

provider "cloudinit" "this" {
}

provider "null" "this" {
}

provider "time" "this" {
}
