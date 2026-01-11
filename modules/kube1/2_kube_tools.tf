terraform {
  required_providers {  
    kubernetes = {
    source = "hashicorp/kubernetes"
    version = "3.0.1"
  }
  }
}


resource "kubernetes_secret_v1" "vault_license" {
  data = {
      license = "02MV4UU43BK5HGYYTOJZWFQMTMNNEWU33JJVCGI3KNNVFGWTKUJF2E2R2NGVHUGMDXJVCGONKMK5GXOT2UKV2E43KGNFGTEVJUJZDUK6KOPJTTKSLJO5UVSM2WPJSEOOLULJMEUZTBK5IWST3JJJVVUV2KNFMXUQLXJVUTC3KZK5HG2TCUJJVU4R2ZORGUOWJSJZBTANKZPJATITTNKE2U46S2NJGTEULJJRBUU4DCNZHDAWKXPBZVSWCSOBRDENLGMFLVC2KPNFEXCSLJO5UWCWCOPJSFOVTGMRDWY5C2KNETMSLKJF3U22SVORGVIRLUJVVFEVKNNJCTMTLKIE3E26SROVHEIQLXJ5CECM2NKRETGV3JJFZUS3SOGBMVQSRQLAZVE4DCK5KWST3JJF4U2RCJGFGFIRLYJRKESMCWIRAXOT3KIF3U62SBO5LWSSLTJFWVMNDDI5WHSWKYKJYGEMRVMZSEO3DULJJUSNSJNJEXOTLKLF2E2VCJORGXURSVJVCECNSNIRATMTKEIJQUS2LXNFSEOVTZMJLWY5KZLBJHAYRSGVTGIR3MORNFGSJWJFVES52NNJMXITKUJF2E26SGKVGUIQJWJVCECNSNIRBGCSLJO5UWGSCKOZNEQVTKMRBUSNSJNZNGQZCXPAYES2LXNFNG26DILIZU22KPNZZWSYSXHFVWIV3YNRRXSSJWK54UU5DEK54DAYKTGFVVS6JRPJMTERTTLJJUS42JNVSHMZDNKZ4WE3KGOVMTEVLUMNDTS43BK5HDKSLJO5UVSV2SGJMVONLKLJLVC5C2I5DDAWKTGF3WG3JZGBNFOTRQMFLTS5KMLBJHSWKXGV5FU3JZPFRFGSLTJFWUM23ENVDHKWJSKZVUYV2SNBSEORLUMNEEU5TEI5LGUZCHNR3GE2JROJNFQ23UMJLUM5KZK5SGYYSXKZ2WIQ2KMRTFQMB5FZUFO2RZGRGGOUBPIRVC62DUNNRFMSDOJZHVQWDUGFHUGSLDKJYGMVCBN5CWEOKJOVTW2Z3FNYYXC6TCMZEEOS2EIZCGQ5T2KF2C66SWMFLGSV2ZGJBUS53OOFWWSOCNF5REEOLEIJFDCZCBNNRWCNDEKYYDGMZYKB3W2VTMMF3EUUBUOBFHQSKJHFCDMVKGJRKWCVSQNJVVOSTUMNCDM4DBNQ3G6T3GI5XEWMT2KBFUUUTNI5EFMM3FLJ3XCRTFFNXTO2ZPOMVUCVCONBIFUZ2TF5FVMWLHF5FSW3CHKB3UYN3KIJ4ESN2HJ5QWWNSVMFUWCSDPMVVTAUSUN43TERCRHU6Q"
      test = "testvalue"
  }
  metadata {
    name      = "vault-license"
    namespace = kubernetes_namespace_v1.simple_app.metadata.0.name
  }
  type = "Opaque"

}

resource "kubernetes_namespace_v1" "simple_app" {
  metadata {
    name = "simple-app"
  }
}

resource "aws_eip" "nginx_ingress" {
  count = 3
  depends_on = [
    kubernetes_namespace_v1.simple_app,
  ]
}

resource "time_sleep" "eip_wait" {
  depends_on = [
    aws_eip.nginx_ingress
  ]
  destroy_duration = "60s"
}

resource "helm_release" "nginx_ingress" {
  depends_on = [
    time_sleep.eip_wait
  ]
  name            = "ingress-nginx"
  repository      = "https://kubernetes.github.io/ingress-nginx"
  chart           = "ingress-nginx"
  upgrade_install = true
  values = [<<-EOT
controller:
  service:
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-backend-protocol: tcp
      service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: true
      service.beta.kubernetes.io/aws-load-balancer-eip-allocations: ${aws_eip.nginx_ingress[0].id},${aws_eip.nginx_ingress[1].id},${aws_eip.nginx_ingress[2].id}
      service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
      service.beta.kubernetes.io/aws-load-balancer-type: nlb
    type: LoadBalancer
defaultBackend:
  enabled: true
EOT
  ]
}

resource "kubernetes_service_account_v1" "vault" {
  metadata {
    name      = "vault-auth"
    namespace = kubernetes_namespace_v1.simple_app.metadata.0.name
  }
  automount_service_account_token = true
}

resource "kubernetes_secret_v1" "vault_token" {
  metadata {
    name      = kubernetes_service_account_v1.vault.metadata.0.name
    namespace = kubernetes_namespace_v1.simple_app.metadata.0.name
    annotations = {
      "kubernetes.io/service-account.name" = "vault-auth"
    }
  }
  type                           = "kubernetes.io/service-account-token"
  wait_for_service_account_token = true
}

resource "kubernetes_cluster_role_binding_v1" "vault" {
  #count      = var.step_2 ? 1 : 0
  #depends_on = [time_sleep.step_2]
  metadata {
    name = "role-tokenreview-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "system:auth-delegator"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.vault.metadata.0.name
    namespace = kubernetes_namespace_v1.simple_app.metadata.0.name
  }
}
