################################################################################
# Production environment values.
#
# Loaded automatically by Terraform. Anything not set here takes the default
# from variables.tf.
################################################################################

# ---- Identity and naming -----------------------------------------------------

project        = "aksplat"
environment    = "prod"
location       = "westeurope"
location_short = "weu"

owner               = "platform-engineering"
cost_center         = "CC-4471"
data_classification = "confidential"
criticality         = "tier-1"

# Source repository for this configuration.
repository_url = "https://github.com/plamenshopov/aks-platform"

additional_tags = {
  service_tier = "platform"
  review_cycle = "quarterly"
}

# ---- Networking --------------------------------------------------------------

vnet_address_space            = ["10.60.0.0/16"]
subnet_system_nodes_cidr      = "10.60.0.0/22"
subnet_user_nodes_cidr        = "10.60.4.0/22"
subnet_private_endpoints_cidr = "10.60.8.0/24"
subnet_ingress_cidr           = "10.60.9.0/24"

# VPN gateway range that platform engineers reach the control plane from.
# Replace with the real gateway CIDR before this leaves a review branch.
admin_cidr = "95.43.222.100/32"

service_cidr   = "172.16.0.0/16"
dns_service_ip = "172.16.0.10"
pod_cidr       = "192.168.0.0/16"

# ---- Cluster -----------------------------------------------------------------

aks_sku_tier                  = "Free"
aks_automatic_upgrade_channel = "patch"
aks_node_os_upgrade_channel   = "NodeImage"
aks_network_policy            = "calico"

# Entra ID group granted cluster-admin. Populate with the object ID of
# aks-prod-admins created during tenant bootstrap:
#
#   az ad group show --group "aks-prod-admins" --query id -o tsv
#
aks_admin_group_object_ids = ["a3529b8a-dfd5-4c0f-a0b7-0d41c30365f2"]

# ---- Node pools --------------------------------------------------------------

system_node_vm_size         = "Standard_D2s_v3"
system_node_count           = 1
system_node_min_count       = 1
system_node_max_count       = 3
system_node_os_disk_size_gb = 64
system_node_max_pods        = 60
system_node_zones           = ["3"]

# The user pool is declared and scaled to zero. The pool exists in the cluster
# and in the configuration — the autoscaler brings nodes up on demand — but it
# costs nothing while idle.
user_node_vm_size         = "Standard_D2s_v3"
user_node_count           = 0
user_node_min_count       = 0
user_node_max_count       = 5
user_node_os_disk_size_gb = 128
user_node_max_pods        = 60
user_node_zones           = ["3"]

# ---- Key Vault ---------------------------------------------------------------

key_vault_sku                        = "standard"
key_vault_soft_delete_retention_days = 90
key_vault_network_default_action     = "Allow"
key_vault_allowed_ip_ranges          = []

etcd_key_type = "RSA"
etcd_key_size = 4096

# ---- Storage -----------------------------------------------------------------

storage_account_tier        = "Standard"
storage_replication_type    = "ZRS"
storage_blob_retention_days = 30

# ---- Observability -----------------------------------------------------------

log_analytics_sku            = "PerGB2018"
log_analytics_retention_days = 30
log_analytics_daily_quota_gb = 5

alert_email                 = "platform-oncall@example.com"
alert_node_cpu_threshold    = 85
alert_node_memory_threshold = 90

# ---- Workload identity -------------------------------------------------------

workload_namespace       = "payments"
workload_service_account = "payments-api"

external_dns_namespace       = "platform-system"
external_dns_service_account = "external-dns"

private_dns_zone_name = "internal.platform.local"

# ---- Maintenance -------------------------------------------------------------

maintenance_day_of_week    = "Sunday"
maintenance_start_time     = "02:00"
maintenance_duration_hours = 4
