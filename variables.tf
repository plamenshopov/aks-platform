################################################################################
# Input variables
#
# Defaults describe the production platform. Environment-specific overrides live
# in prod.auto.tfvars. Every variable that can be validated cheaply is validated
# here so that a bad value fails at plan time rather than half way through an
# apply.
################################################################################

################################################################################
# Subscription and identity
################################################################################

variable "subscription_id" {
  description = <<-EOT
    Azure subscription the platform is deployed into. Leave null in CI, where
    the value is supplied by ARM_SUBSCRIPTION_ID from repository variables.
  EOT
  type        = string
  default     = null
}

################################################################################
# Naming and tagging
################################################################################

variable "project" {
  description = "Short project identifier. Used as the first segment of every resource name."
  type        = string
  default     = "aksplat"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,11}$", var.project))
    error_message = "project must be 3-12 lowercase alphanumeric characters and start with a letter."
  }
}

variable "environment" {
  description = "Deployment environment. Drives naming, tagging and a number of sizing defaults."
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "test", "stage", "prod"], var.environment)
    error_message = "environment must be one of: dev, test, stage, prod."
  }
}

variable "location" {
  description = "Azure region for all regional resources."
  type        = string
  default     = "westeurope"
}

variable "location_short" {
  description = "Abbreviated region code used in resource names, e.g. weu for West Europe."
  type        = string
  default     = "weu"

  validation {
    condition     = can(regex("^[a-z]{2,4}$", var.location_short))
    error_message = "location_short must be 2-4 lowercase letters."
  }
}

variable "owner" {
  description = "Team accountable for this platform. Applied as a tag to every resource."
  type        = string
  default     = "platform-engineering"
}

variable "cost_center" {
  description = "Finance cost centre code. Applied as a tag and used for chargeback reporting."
  type        = string
  default     = "CC-4471"
}

variable "data_classification" {
  description = "Highest data classification the platform is approved to process."
  type        = string
  default     = "confidential"

  validation {
    condition     = contains(["public", "internal", "confidential", "restricted"], var.data_classification)
    error_message = "data_classification must be one of: public, internal, confidential, restricted."
  }
}

variable "criticality" {
  description = "Business criticality tier, used by the on-call rota and DR planning."
  type        = string
  default     = "tier-1"

  validation {
    condition     = contains(["tier-1", "tier-2", "tier-3"], var.criticality)
    error_message = "criticality must be one of: tier-1, tier-2, tier-3."
  }
}

variable "repository_url" {
  description = "Source repository for this configuration. Applied as a tag so operators can find the code."
  type        = string
  default     = "https://github.com/plamenshopov/aks-platform"
}

variable "additional_tags" {
  description = "Extra tags merged over the standard tag set."
  type        = map(string)
  default     = {}
}

################################################################################
# Networking
################################################################################

variable "vnet_address_space" {
  description = "Address space for the platform virtual network."
  type        = list(string)
  default     = ["10.60.0.0/16"]

  validation {
    condition     = alltrue([for cidr in var.vnet_address_space : can(cidrhost(cidr, 0))])
    error_message = "Every entry in vnet_address_space must be a valid CIDR block."
  }
}

variable "subnet_system_nodes_cidr" {
  description = "Subnet for the AKS system node pool."
  type        = string
  default     = "10.60.0.0/22"

  validation {
    condition     = can(cidrhost(var.subnet_system_nodes_cidr, 0))
    error_message = "subnet_system_nodes_cidr must be a valid CIDR block."
  }
}

variable "subnet_user_nodes_cidr" {
  description = "Subnet for the AKS user node pool."
  type        = string
  default     = "10.60.4.0/22"

  validation {
    condition     = can(cidrhost(var.subnet_user_nodes_cidr, 0))
    error_message = "subnet_user_nodes_cidr must be a valid CIDR block."
  }
}

variable "subnet_private_endpoints_cidr" {
  description = "Subnet holding private endpoints for platform PaaS services."
  type        = string
  default     = "10.60.8.0/24"

  validation {
    condition     = can(cidrhost(var.subnet_private_endpoints_cidr, 0))
    error_message = "subnet_private_endpoints_cidr must be a valid CIDR block."
  }
}

variable "subnet_ingress_cidr" {
  description = "Subnet reserved for the ingress tier. Provisioned ahead of the gateway rollout."
  type        = string
  default     = "10.60.9.0/24"

  validation {
    condition     = can(cidrhost(var.subnet_ingress_cidr, 0))
    error_message = "subnet_ingress_cidr must be a valid CIDR block."
  }
}

variable "admin_cidr" {
  description = <<-EOT
    VPN gateway CIDR that is permitted to reach the Kubernetes API server.
    Platform standard: the control plane is never reachable from outside this
    range.
  EOT
  type        = string
  default     = "203.0.113.0/24"

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0))
    error_message = "admin_cidr must be a valid CIDR block."
  }
}

variable "service_cidr" {
  description = "Kubernetes service CIDR. Must not overlap the virtual network or the pod CIDR."
  type        = string
  default     = "172.16.0.0/16"

  validation {
    condition     = can(cidrhost(var.service_cidr, 0))
    error_message = "service_cidr must be a valid CIDR block."
  }
}

variable "dns_service_ip" {
  description = "Cluster DNS service address. Must sit inside service_cidr."
  type        = string
  default     = "172.16.0.10"
}

variable "pod_cidr" {
  description = "Overlay pod CIDR. Not routable on the virtual network."
  type        = string
  default     = "192.168.0.0/16"

  validation {
    condition     = can(cidrhost(var.pod_cidr, 0))
    error_message = "pod_cidr must be a valid CIDR block."
  }
}

################################################################################
# AKS — cluster
################################################################################

variable "kubernetes_version" {
  description = <<-EOT
    Kubernetes minor version for the control plane. Leave null to take the
    region default, which is what the platform team does between upgrade
    windows.
  EOT
  type        = string
  default     = null
}

variable "aks_sku_tier" {
  description = "Control plane SKU. Free carries no uptime SLA; Standard is required for production workloads."
  type        = string
  default     = "Free"

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.aks_sku_tier)
    error_message = "aks_sku_tier must be one of: Free, Standard, Premium."
  }
}

variable "aks_automatic_upgrade_channel" {
  description = "Control plane auto-upgrade channel."
  type        = string
  default     = "patch"

  validation {
    condition     = contains(["none", "patch", "rapid", "stable", "node-image"], var.aks_automatic_upgrade_channel)
    error_message = "aks_automatic_upgrade_channel must be one of: none, patch, rapid, stable, node-image."
  }
}

variable "aks_node_os_upgrade_channel" {
  description = "Node OS image auto-upgrade channel."
  type        = string
  default     = "NodeImage"

  validation {
    condition     = contains(["None", "Unmanaged", "SecurityPatch", "NodeImage"], var.aks_node_os_upgrade_channel)
    error_message = "aks_node_os_upgrade_channel must be one of: None, Unmanaged, SecurityPatch, NodeImage."
  }
}

variable "aks_network_policy" {
  description = "Network policy engine for pod-to-pod traffic control."
  type        = string
  default     = "azure"

  validation {
    condition     = contains(["azure", "calico"], var.aks_network_policy)
    error_message = "aks_network_policy must be one of: azure, calico."
  }
}

variable "aks_admin_group_object_ids" {
  description = <<-EOT
    Entra ID group object IDs granted cluster-admin. Membership is managed in
    Entra, not in the cluster, so that joiners and leavers are handled by the
    existing identity lifecycle.
  EOT
  type        = list(string)
  default     = []
}

variable "aks_diagnostic_log_categories" {
  description = <<-EOT
    Control plane log categories shipped to Log Analytics. kube-audit is
    deliberately excluded: it is high volume and expensive, and kube-audit-admin
    covers the mutating operations we need for forensics.
  EOT
  type        = list(string)
  default = [
    "kube-apiserver",
    "kube-audit-admin",
    "kube-controller-manager",
    "kube-scheduler",
    "cluster-autoscaler",
  ]
}

################################################################################
# AKS — system node pool
################################################################################

variable "system_node_vm_size" {
  description = "VM size for the system node pool."
  type        = string
  default     = "Standard_D2s_v3"
}

variable "system_node_count" {
  description = "Initial node count for the system pool. The autoscaler owns this value after creation."
  type        = number
  default     = 1

  validation {
    condition     = var.system_node_count >= 1 && var.system_node_count <= 10
    error_message = "system_node_count must be between 1 and 10."
  }
}

variable "system_node_min_count" {
  description = "Autoscaler floor for the system pool."
  type        = number
  default     = 1
}

variable "system_node_max_count" {
  description = "Autoscaler ceiling for the system pool."
  type        = number
  default     = 3
}

variable "system_node_os_disk_size_gb" {
  description = "OS disk size for system nodes."
  type        = number
  default     = 64

  validation {
    condition     = var.system_node_os_disk_size_gb >= 30 && var.system_node_os_disk_size_gb <= 2048
    error_message = "system_node_os_disk_size_gb must be between 30 and 2048."
  }
}

variable "system_node_max_pods" {
  description = "Maximum pods per system node."
  type        = number
  default     = 60
}

variable "system_node_zones" {
  description = "Availability zones for the system pool. The region must support zones."
  type        = list(string)
  default     = ["3"]
}

################################################################################
# AKS — user node pool
################################################################################

variable "user_node_vm_size" {
  description = "VM size for the user node pool."
  type        = string
  default     = "Standard_D2s_v3"
}

variable "user_node_count" {
  description = "Initial node count for the user pool. The autoscaler owns this value after creation."
  type        = number
  default     = 1
}

variable "user_node_min_count" {
  description = "Autoscaler floor for the user pool."
  type        = number
  default     = 1
}

variable "user_node_max_count" {
  description = "Autoscaler ceiling for the user pool."
  type        = number
  default     = 5
}

variable "user_node_os_disk_size_gb" {
  description = "OS disk size for user nodes."
  type        = number
  default     = 128
}

variable "user_node_max_pods" {
  description = "Maximum pods per user node."
  type        = number
  default     = 60
}

variable "user_node_zones" {
  description = "Availability zones for the user pool."
  type        = list(string)
  default     = ["3"]
}

################################################################################
# Key Vault
################################################################################

variable "key_vault_sku" {
  description = "Key Vault SKU. Premium is required for HSM-backed keys."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "key_vault_sku must be one of: standard, premium."
  }
}

variable "key_vault_soft_delete_retention_days" {
  description = "Soft-delete retention window for the vault."
  type        = number
  default     = 90

  validation {
    condition     = var.key_vault_soft_delete_retention_days >= 7 && var.key_vault_soft_delete_retention_days <= 90
    error_message = "key_vault_soft_delete_retention_days must be between 7 and 90."
  }
}

variable "key_vault_network_default_action" {
  description = <<-EOT
    Default network ACL action for the vault. Kept at Allow while the control
    plane integration path is finalised; the vault is protected by Entra ID RBAC
    and no key material can be exported.
  EOT
  type        = string
  default     = "Allow"

  validation {
    condition     = contains(["Allow", "Deny"], var.key_vault_network_default_action)
    error_message = "key_vault_network_default_action must be Allow or Deny."
  }
}

variable "key_vault_allowed_ip_ranges" {
  description = "Additional IP ranges permitted to reach the vault when the default action is Deny."
  type        = list(string)
  default     = []
}

variable "etcd_key_type" {
  description = "Key type for the etcd encryption key."
  type        = string
  default     = "RSA"

  validation {
    condition     = contains(["RSA", "RSA-HSM"], var.etcd_key_type)
    error_message = "etcd_key_type must be RSA or RSA-HSM."
  }
}

variable "etcd_key_size" {
  description = "Key size in bits for the etcd encryption key."
  type        = number
  default     = 4096

  validation {
    condition     = contains([2048, 3072, 4096], var.etcd_key_size)
    error_message = "etcd_key_size must be 2048, 3072 or 4096."
  }
}

################################################################################
# Storage
################################################################################

variable "storage_account_tier" {
  description = "Performance tier for the platform storage account."
  type        = string
  default     = "Standard"
}

variable "storage_replication_type" {
  description = "Replication strategy for the platform storage account."
  type        = string
  default     = "ZRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "GZRS"], var.storage_replication_type)
    error_message = "storage_replication_type must be one of: LRS, ZRS, GRS, GZRS."
  }
}

variable "storage_blob_retention_days" {
  description = "Soft-delete retention for blobs."
  type        = number
  default     = 30

  validation {
    condition     = var.storage_blob_retention_days >= 1 && var.storage_blob_retention_days <= 365
    error_message = "storage_blob_retention_days must be between 1 and 365."
  }
}

################################################################################
# Observability
################################################################################

variable "log_analytics_sku" {
  description = "Log Analytics workspace pricing tier."
  type        = string
  default     = "PerGB2018"
}

variable "log_analytics_retention_days" {
  description = "Log retention in days."
  type        = number
  default     = 30

  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "log_analytics_retention_days must be between 30 and 730."
  }
}

variable "log_analytics_daily_quota_gb" {
  description = "Daily ingestion cap in GB. -1 disables the cap."
  type        = number
  default     = 5
}

variable "alert_email" {
  description = "Address that receives platform alerts."
  type        = string
  default     = "platform-oncall@example.com"

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email must be a valid email address."
  }
}

variable "alert_node_cpu_threshold" {
  description = "Average node CPU percentage that triggers a warning alert."
  type        = number
  default     = 85

  validation {
    condition     = var.alert_node_cpu_threshold > 0 && var.alert_node_cpu_threshold <= 100
    error_message = "alert_node_cpu_threshold must be between 1 and 100."
  }
}

variable "alert_node_memory_threshold" {
  description = "Average node working-set memory percentage that triggers a warning alert."
  type        = number
  default     = 90

  validation {
    condition     = var.alert_node_memory_threshold > 0 && var.alert_node_memory_threshold <= 100
    error_message = "alert_node_memory_threshold must be between 1 and 100."
  }
}

################################################################################
# Workload identity
################################################################################

variable "workload_namespace" {
  description = "Kubernetes namespace of the first onboarded workload."
  type        = string
  default     = "payments"
}

variable "workload_service_account" {
  description = "Kubernetes service account federated to the workload managed identity."
  type        = string
  default     = "payments-api"
}

variable "external_dns_namespace" {
  description = "Namespace running the external-dns controller."
  type        = string
  default     = "platform-system"
}

variable "external_dns_service_account" {
  description = "Service account used by the external-dns controller."
  type        = string
  default     = "external-dns"
}

variable "private_dns_zone_name" {
  description = "Private DNS zone managed by the platform for internal service records."
  type        = string
  default     = "internal.platform.local"
}

################################################################################
# Maintenance
################################################################################

variable "maintenance_day_of_week" {
  description = "Day on which control plane auto-upgrades are permitted."
  type        = string
  default     = "Sunday"

  validation {
    condition = contains(
      ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"],
      var.maintenance_day_of_week,
    )
    error_message = "maintenance_day_of_week must be a full English weekday name."
  }
}

variable "maintenance_start_time" {
  description = "Start of the maintenance window in 24-hour HH:MM form, UTC."
  type        = string
  default     = "02:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.maintenance_start_time))
    error_message = "maintenance_start_time must be in HH:MM 24-hour format."
  }
}

variable "maintenance_duration_hours" {
  description = "Length of the maintenance window in hours."
  type        = number
  default     = 4

  validation {
    condition     = var.maintenance_duration_hours >= 4 && var.maintenance_duration_hours <= 24
    error_message = "maintenance_duration_hours must be between 4 and 24."
  }
}
