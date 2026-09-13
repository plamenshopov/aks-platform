################################################################################
# Outputs
#
# Consumed by the platform GitOps repository and by the on-call runbooks. Values
# that would expose credentials are deliberately not surfaced here — cluster
# credentials are obtained through Entra ID, not read out of Terraform state.
################################################################################

################################################################################
# Cluster
################################################################################

output "cluster_name" {
  description = "Name of the managed cluster."
  value       = azurerm_kubernetes_cluster.this.name
}

output "cluster_id" {
  description = "Resource ID of the managed cluster."
  value       = azurerm_kubernetes_cluster.this.id
}

output "cluster_fqdn" {
  description = "Public FQDN of the Kubernetes API server."
  value       = azurerm_kubernetes_cluster.this.fqdn
}

output "cluster_kubernetes_version" {
  description = "Kubernetes version currently running on the control plane."
  value       = azurerm_kubernetes_cluster.this.kubernetes_version
}

output "cluster_node_resource_group" {
  description = "Resource group AKS manages node infrastructure in."
  value       = azurerm_kubernetes_cluster.this.node_resource_group
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL used to federate workload identities to this cluster."
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "cluster_identity_principal_id" {
  description = "Principal ID of the control plane managed identity."
  value       = azurerm_kubernetes_cluster.this.identity[0].principal_id
}

output "cluster_kubelet_identity_object_id" {
  description = "Object ID of the kubelet identity used by nodes."
  value       = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}

################################################################################
# Networking
################################################################################

output "virtual_network_id" {
  description = "Resource ID of the platform virtual network."
  value       = azurerm_virtual_network.this.id
}

output "subnet_ids" {
  description = "Map of subnet purpose to resource ID."
  value = {
    system_nodes      = azurerm_subnet.system_nodes.id
    user_nodes        = azurerm_subnet.user_nodes.id
    private_endpoints = azurerm_subnet.private_endpoints.id
    ingress           = azurerm_subnet.ingress.id
  }
}

output "private_dns_zone_internal_name" {
  description = "Internal private DNS zone that external-dns reconciles records into."
  value       = azurerm_private_dns_zone.internal.name
}

################################################################################
# Key material
################################################################################

output "key_vault_name" {
  description = "Name of the platform key vault."
  value       = azurerm_key_vault.this.name
}

output "key_vault_uri" {
  description = "Data-plane URI of the platform key vault."
  value       = azurerm_key_vault.this.vault_uri
}

output "etcd_key_id" {
  description = "Versioned resource ID of the customer-managed key provisioned for etcd encryption."
  value       = azurerm_key_vault_key.etcd.id
}

output "workload_key_id" {
  description = "Versioned resource ID of the workload envelope encryption key."
  value       = azurerm_key_vault_key.workload.id
}

################################################################################
# Workload identity
################################################################################

output "workload_identity_client_id" {
  description = "Client ID the payments API service account exchanges its token for."
  value       = azurerm_user_assigned_identity.workload.client_id
}

output "external_dns_identity_client_id" {
  description = "Client ID used by the external-dns controller."
  value       = azurerm_user_assigned_identity.external_dns.client_id
}

################################################################################
# Observability and storage
################################################################################

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace."
  value       = azurerm_log_analytics_workspace.this.id
}

output "storage_account_name" {
  description = "Name of the platform storage account."
  value       = azurerm_storage_account.this.name
}

output "storage_account_blob_endpoint" {
  description = "Primary blob endpoint for the platform storage account."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}
