################################################################################
# Workload identities.
#
# Pods authenticate to Azure with federated credentials rather than secrets: a
# Kubernetes service account token is exchanged for an Entra ID token, so there
# is no client secret to rotate, leak or find in a manifest.
#
# Each identity is scoped to exactly one namespace and service account. Widening
# a subject to a wildcard would let any pod in the cluster assume the identity.
################################################################################

################################################################################
# Payments API — the first onboarded application workload
################################################################################

resource "azurerm_user_assigned_identity" "workload" {
  name                = "id-${local.name_prefix}-workload"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.common_tags
}

resource "azurerm_federated_identity_credential" "workload" {
  name                      = "fic-${local.name_prefix}-workload"
  user_assigned_identity_id = azurerm_user_assigned_identity.workload.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = azurerm_kubernetes_cluster.this.oidc_issuer_url
  subject                   = "system:serviceaccount:${var.workload_namespace}:${var.workload_service_account}"
}

resource "azurerm_role_assignment" "workload_key_vault_secrets" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.workload.principal_id
  principal_type       = "ServicePrincipal"

  description = "Read-only access to application secrets for the payments API."
}

resource "azurerm_role_assignment" "workload_storage_reader" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.workload.principal_id
  principal_type       = "ServicePrincipal"

  description = "Read-only access to platform blob data for the payments API."
}

################################################################################
# external-dns — writes service records into the internal private DNS zone
################################################################################

resource "azurerm_user_assigned_identity" "external_dns" {
  name                = "id-${local.name_prefix}-external-dns"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.common_tags
}

resource "azurerm_federated_identity_credential" "external_dns" {
  name                      = "fic-${local.name_prefix}-external-dns"
  user_assigned_identity_id = azurerm_user_assigned_identity.external_dns.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = azurerm_kubernetes_cluster.this.oidc_issuer_url
  subject                   = "system:serviceaccount:${var.external_dns_namespace}:${var.external_dns_service_account}"
}

resource "azurerm_role_assignment" "external_dns_zone_contributor" {
  scope                = azurerm_private_dns_zone.internal.id
  role_definition_name = "Private DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.external_dns.principal_id
  principal_type       = "ServicePrincipal"

  description = "Allows external-dns to reconcile service records in the internal zone."
}

resource "azurerm_role_assignment" "external_dns_network_reader" {
  scope                = azurerm_resource_group.this.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.external_dns.principal_id
  principal_type       = "ServicePrincipal"

  description = "external-dns enumerates the resource group to discover the target zone."
}

################################################################################
# Kubelet identity — image pulls and node-level Azure access
#
# AKS creates this identity in the node resource group. It is surfaced here so
# that role assignments granted to it are visible in this configuration rather
# than being applied out of band.
################################################################################

resource "azurerm_role_assignment" "kubelet_key_vault_secrets" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
  principal_type       = "ServicePrincipal"

  description = "Allows nodes to resolve image pull secrets held in the platform vault."
}
