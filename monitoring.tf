################################################################################
# Observability: log workspace, diagnostic settings, alert routing and alerts.
################################################################################

resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${local.name_prefix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  tags                = local.common_tags

  # A daily cap is the difference between a noisy week and a five-figure
  # surprise. Alerts on the cap itself are wired up below.
  daily_quota_gb = var.log_analytics_daily_quota_gb

  internet_ingestion_enabled = true
  internet_query_enabled     = true
}

################################################################################
# Control plane diagnostics
#
# kube-audit is intentionally absent from the default category list: it is the
# single largest ingestion source on a busy cluster and kube-audit-admin covers
# the mutating operations needed for incident review.
################################################################################

resource "azurerm_monitor_diagnostic_setting" "aks" {
  name                       = "diag-aks"
  target_resource_id         = azurerm_kubernetes_cluster.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  dynamic "enabled_log" {
    for_each = toset(var.aks_diagnostic_log_categories)

    content {
      category = enabled_log.value
    }
  }
}

################################################################################
# Network security group diagnostics
################################################################################

resource "azurerm_monitor_diagnostic_setting" "nsg" {
  for_each = {
    system-nodes = azurerm_network_security_group.system_nodes.id
    user-nodes   = azurerm_network_security_group.user_nodes.id
    ingress      = azurerm_network_security_group.ingress.id
  }

  name                       = "diag-nsg-${each.key}"
  target_resource_id         = each.value
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category = "NetworkSecurityGroupEvent"
  }

  enabled_log {
    category = "NetworkSecurityGroupRuleCounter"
  }
}

################################################################################
# Alert routing
################################################################################

resource "azurerm_monitor_action_group" "this" {
  name                = "ag-${local.name_prefix}-platform"
  resource_group_name = azurerm_resource_group.this.name
  short_name          = "platform"
  tags                = local.common_tags

  email_receiver {
    name                    = "platform-oncall"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }
}

################################################################################
# Resource health and capacity alerts
################################################################################

resource "azurerm_monitor_metric_alert" "node_cpu" {
  name                = "alert-${local.name_prefix}-node-cpu"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [azurerm_kubernetes_cluster.this.id]
  description         = "Average node CPU utilisation is sustained above the capacity threshold."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.ContainerService/managedClusters"
    metric_name      = "node_cpu_usage_percentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.alert_node_cpu_threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
}

resource "azurerm_monitor_metric_alert" "node_memory" {
  name                = "alert-${local.name_prefix}-node-memory"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [azurerm_kubernetes_cluster.this.id]
  description         = "Average node working set memory is sustained above the capacity threshold."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.ContainerService/managedClusters"
    metric_name      = "node_memory_working_set_percentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.alert_node_memory_threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
}

################################################################################
# Change alerts
#
# Deletion of the cluster or the vault is never a routine operation. These fire
# on the activity log regardless of who or what initiated the change, including
# automation running with valid credentials.
################################################################################

resource "azurerm_monitor_activity_log_alert" "cluster_delete" {
  name                = "alert-${local.name_prefix}-cluster-delete"
  resource_group_name = azurerm_resource_group.this.name
  location            = "global"
  scopes              = [azurerm_resource_group.this.id]
  description         = "A delete was issued against the managed cluster."
  tags                = local.common_tags

  criteria {
    category       = "Administrative"
    operation_name = "Microsoft.ContainerService/managedClusters/delete"
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
}

resource "azurerm_monitor_activity_log_alert" "key_vault_delete" {
  name                = "alert-${local.name_prefix}-key-vault-delete"
  resource_group_name = azurerm_resource_group.this.name
  location            = "global"
  scopes              = [azurerm_resource_group.this.id]
  description         = "A delete was issued against the platform key vault."
  tags                = local.common_tags

  criteria {
    category       = "Administrative"
    operation_name = "Microsoft.KeyVault/vaults/delete"
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
}

resource "azurerm_monitor_activity_log_alert" "service_health" {
  name                = "alert-${local.name_prefix}-service-health"
  resource_group_name = azurerm_resource_group.this.name
  location            = "global"
  scopes              = [data.azurerm_subscription.current.id]
  description         = "Azure service health incidents affecting the platform region."
  tags                = local.common_tags

  criteria {
    category = "ServiceHealth"

    service_health {
      events    = ["Incident", "Maintenance"]
      locations = [var.location]
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
}
