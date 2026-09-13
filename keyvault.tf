################################################################################
# Key Vault and platform key material.
#
# Access is governed by Entra ID RBAC rather than vault access policies, so that
# key permissions are visible in the same place as every other Azure role
# assignment.
#
# Purge protection is mandatory here and is not a preference: a vault holding a
# key that encrypts cluster state must not be permanently deletable while that
# state exists. Note that this makes the vault name unrecoverable for the
# soft-delete retention window after a destroy, which is why the name carries a
# random suffix.
################################################################################

resource "azurerm_key_vault" "this" {
  name                = local.key_vault_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = var.key_vault_sku
  tags                = local.common_tags

  rbac_authorization_enabled = true
  purge_protection_enabled   = true
  soft_delete_retention_days = var.key_vault_soft_delete_retention_days

  enabled_for_disk_encryption     = true
  enabled_for_deployment          = false
  enabled_for_template_deployment = false

  public_network_access_enabled = true

  network_acls {
    bypass         = "AzureServices"
    default_action = var.key_vault_network_default_action
    ip_rules       = var.key_vault_allowed_ip_ranges

    virtual_network_subnet_ids = [
      azurerm_subnet.system_nodes.id,
      azurerm_subnet.user_nodes.id,
    ]
  }
}

################################################################################
# etcd encryption key
#
# Provisioned by the platform team as part of the customer-managed key
# programme. Rotation is manual and tracked in the platform runbook.
################################################################################

resource "azurerm_key_vault_key" "etcd" {
  name         = "key-${local.name_prefix}-etcd"
  key_vault_id = azurerm_key_vault.this.id
  key_type     = var.etcd_key_type
  key_size     = var.etcd_key_size
  tags         = local.common_tags

  key_opts = [
    "decrypt",
    "encrypt",
    "unwrapKey",
    "wrapKey",
  ]
}

################################################################################
# Application secrets key
#
# Used by the CSI secrets store driver for envelope encryption of workload
# secrets synced into the cluster.
################################################################################

resource "azurerm_key_vault_key" "workload" {
  name         = "key-${local.name_prefix}-workload"
  key_vault_id = azurerm_key_vault.this.id
  key_type     = "RSA"
  key_size     = 2048
  tags         = local.common_tags

  key_opts = [
    "decrypt",
    "encrypt",
    "unwrapKey",
    "wrapKey",
  ]
}

################################################################################
# Role assignments
#
# The Terraform service principal holds Key Vault Administrator at subscription
# scope from the bootstrap step, so it is not re-granted here.
################################################################################

# The cluster control plane identity needs crypto permissions on the vault in
# order to wrap and unwrap the etcd data encryption key.
resource "azurerm_role_assignment" "aks_key_vault_crypto_user" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Crypto User"
  principal_id         = azurerm_kubernetes_cluster.this.identity[0].principal_id
  principal_type       = "ServicePrincipal"

  description = "Allows the AKS control plane to use platform keys for envelope encryption."
}

# The secrets store CSI driver identity reads secrets and unwraps the workload
# key on behalf of application pods.
resource "azurerm_role_assignment" "aks_secrets_provider_key_vault_user" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_kubernetes_cluster.this.key_vault_secrets_provider[0].secret_identity[0].object_id
  principal_type       = "ServicePrincipal"

  description = "Allows the CSI secrets store driver to read secrets for mounted volumes."
}

################################################################################
# Diagnostics
################################################################################

resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  name                       = "diag-key-vault"
  target_resource_id         = azurerm_key_vault.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category = "AuditEvent"
  }

  enabled_log {
    category = "AzurePolicyEvaluationDetails"
  }
}
