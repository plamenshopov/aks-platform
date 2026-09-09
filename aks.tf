################################################################################
# Azure Kubernetes Service — production control plane and node pools.
#
# Networking uses Azure CNI in overlay mode: pods draw from a non-routable
# overlay CIDR, so node subnets only have to be sized for nodes and endpoints.
# The node resource group name is set explicitly so support tooling and cost
# reports do not depend on the generated MC_* name.
################################################################################

resource "azurerm_kubernetes_cluster" "this" {
  name                = "aks-${local.name_prefix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  dns_prefix          = "aks-${local.name_prefix}"
  node_resource_group = local.node_resource_group
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.aks_sku_tier
  tags                = local.common_tags

  # ---------------------------------------------------------------------------
  # Upgrade posture
  #
  # Patch upgrades land automatically inside the maintenance window; minor
  # version upgrades remain a deliberate, reviewed change to this file.
  # ---------------------------------------------------------------------------
  automatic_upgrade_channel = var.aks_automatic_upgrade_channel
  node_os_upgrade_channel   = var.aks_node_os_upgrade_channel

  # ---------------------------------------------------------------------------
  # Access model
  #
  # Kubernetes RBAC is on. Role bindings for application teams are reconciled
  # into the cluster from the platform GitOps repository rather than being
  # managed here.
  #
  # The API server is served on a public endpoint. Access is controlled at the
  # network layer.
  # ---------------------------------------------------------------------------
  role_based_access_control_enabled = true
  local_account_disabled            = true
  private_cluster_enabled           = false

  api_server_access_profile {
    authorized_ip_ranges = [var.admin_cidr]
  }

  azure_active_directory_role_based_access_control {
    admin_group_object_ids = var.aks_admin_group_object_ids
    azure_rbac_enabled     = true
  }

  # ---------------------------------------------------------------------------
  # Platform capabilities
  # ---------------------------------------------------------------------------
  oidc_issuer_enabled          = true
  workload_identity_enabled    = true
  azure_policy_enabled         = true
  image_cleaner_enabled        = true
  image_cleaner_interval_hours = 48

  identity {
    type = "SystemAssigned"
  }

  # ---------------------------------------------------------------------------
  # System node pool
  #
  # Carries platform add-ons and application workloads. Autoscaling is enabled,
  # so node_count is only the value the pool is created with — the cluster
  # autoscaler owns it afterwards and Terraform ignores subsequent drift.
  # ---------------------------------------------------------------------------
  default_node_pool {
    name                        = "system"
    vm_size                     = var.system_node_vm_size
    vnet_subnet_id              = azurerm_subnet.system_nodes.id
    zones                       = var.system_node_zones
    auto_scaling_enabled        = true
    node_count                  = var.system_node_count
    min_count                   = var.system_node_min_count
    max_count                   = var.system_node_max_count
    max_pods                    = var.system_node_max_pods
    os_disk_size_gb             = var.system_node_os_disk_size_gb
    os_disk_type                = "Managed"
    os_sku                      = "Ubuntu"
    node_public_ip_enabled      = false
    host_encryption_enabled     = false
    temporary_name_for_rotation = "systemtmp"
    type                        = "VirtualMachineScaleSets"

    node_labels = {
      "platform.internal/pool" = "system"
      "platform.internal/tier" = var.criticality
    }

    upgrade_settings {
      max_surge = "33%"
    }
  }

  # ---------------------------------------------------------------------------
  # Cluster networking
  # ---------------------------------------------------------------------------
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = var.aks_network_policy
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
    pod_cidr            = var.pod_cidr
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
  }

  # ---------------------------------------------------------------------------
  # Observability and storage add-ons
  # ---------------------------------------------------------------------------
  oms_agent {
    log_analytics_workspace_id      = azurerm_log_analytics_workspace.this.id
    msi_auth_for_monitoring_enabled = true
  }

  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "5m"
  }

  key_management_service {
    key_vault_key_id = azurerm_key_vault_key.etcd.id
  }

  workload_autoscaler_profile {
    keda_enabled                    = true
    vertical_pod_autoscaler_enabled = false
  }

  storage_profile {
    blob_driver_enabled         = true
    disk_driver_enabled         = true
    file_driver_enabled         = true
    snapshot_controller_enabled = true
  }

  # ---------------------------------------------------------------------------
  # Autoscaler tuning
  #
  # Scale-down is deliberately unhurried: this platform runs batch workloads
  # that tolerate a warm pool better than they tolerate eviction churn.
  # ---------------------------------------------------------------------------
  auto_scaler_profile {
    balance_similar_node_groups   = true
    expander                      = "least-waste"
    max_graceful_termination_sec  = "600"
    scale_down_delay_after_add    = "15m"
    scale_down_unneeded           = "15m"
    scan_interval                 = "10s"
    skip_nodes_with_local_storage = true
    skip_nodes_with_system_pods   = true
  }

  # ---------------------------------------------------------------------------
  # Maintenance window for automatic control plane upgrades
  # ---------------------------------------------------------------------------
  maintenance_window_auto_upgrade {
    frequency   = "Weekly"
    interval    = 1
    duration    = var.maintenance_duration_hours
    day_of_week = var.maintenance_day_of_week
    start_time  = var.maintenance_start_time
    utc_offset  = "+00:00"
  }

  lifecycle {
    # The cluster autoscaler is the owner of the running node count. Without
    # this, every plan after a scaling event shows a spurious change.
    ignore_changes = [
      default_node_pool[0].node_count,
    ]
  }

  depends_on = [
    azurerm_subnet_network_security_group_association.system_nodes,
    azurerm_subnet_network_security_group_association.user_nodes,
  ]
}

################################################################################
# User node pool
#
# Application workloads run here so that a noisy tenant cannot starve the
# platform add-ons on the system pool.
################################################################################

resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = var.user_node_vm_size
  vnet_subnet_id        = azurerm_subnet.user_nodes.id
  zones                 = var.user_node_zones
  mode                  = "User"
  os_type               = "Linux"
  os_sku                = "Ubuntu"
  os_disk_size_gb       = var.user_node_os_disk_size_gb
  os_disk_type          = "Managed"
  max_pods              = var.user_node_max_pods
  auto_scaling_enabled  = true
  node_count            = var.user_node_count
  min_count             = var.user_node_min_count
  max_count             = var.user_node_max_count

  node_public_ip_enabled  = false
  host_encryption_enabled = false

  # Required for in-place VM size changes. Without it, resizing this pool is a
  # destroy-and-recreate operation.
  temporary_name_for_rotation = "usertmp"

  node_labels = {
    "platform.internal/pool" = "user"
    "platform.internal/tier" = var.criticality
  }

  upgrade_settings {
    max_surge = "33%"
  }

  tags = local.common_tags

  lifecycle {
    ignore_changes = [
      node_count,
    ]
  }
}
