# StorageClass for Vault persistent storage using EBS
resource "kubernetes_storage_class_v1" "vault_storage" {
  metadata {
    name = "vault-storage"
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true
  volume_binding_mode    = "WaitForFirstConsumer"

  parameters = {
    type      = "gp3"
    encrypted = "true"
    fsType    = "ext4"
  }
}
