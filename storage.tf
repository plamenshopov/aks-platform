################################################################################
# Platform storage account.
#
# Holds build artefacts and application blob data. Workload access is over a
# private endpoint; the public endpoint stays reachable so that management-plane
# tooling and the pipeline can read account properties without a line of sight
# into the virtual network.
################################################################################

resource "azurerm_storage_account" "this" {
  name                     = local.storage_account_name
  location                 = azurerm_resource_group.this.location
  resource_group_name      = azurerm_resource_group.this.name
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  access_tier              = "Hot"
  tags                     = local.common_tags

  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = true

  # Double encryption at rest: the platform layer on top of the default
  # infrastructure layer. This cannot be changed after creation.
  infrastructure_encryption_enabled = true

  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true

    delete_retention_policy {
      days = var.storage_blob_retention_days
    }

    container_delete_retention_policy {
      days = var.storage_blob_retention_days
    }
  }

  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices", "Logging", "Metrics"]

    virtual_network_subnet_ids = [
      azurerm_subnet.system_nodes.id,
      azurerm_subnet.user_nodes.id,
    ]
  }

  identity {
    type = "SystemAssigned"
  }
}

################################################################################
# Private endpoint for blob access from the cluster
################################################################################

resource "azurerm_private_endpoint" "storage_blob" {
  name                = "pe-${local.name_prefix}-blob"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.private_endpoints.id
  tags                = local.common_tags

  private_service_connection {
    name                           = "psc-${local.name_prefix}-blob"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
}

################################################################################
# Lifecycle management
#
# Artefacts age out to cool storage and are deleted well inside the retention
# obligation for this data classification.
################################################################################

resource "azurerm_storage_management_policy" "this" {
  storage_account_id = azurerm_storage_account.this.id

  rule {
    name    = "artefact-tiering"
    enabled = true

    filters {
      prefix_match = ["artifacts/"]
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than = 30
        delete_after_days_since_modification_greater_than       = 365
      }

      snapshot {
        delete_after_days_since_creation_greater_than = 90
      }

      version {
        delete_after_days_since_creation = 90
      }
    }
  }

  rule {
    name    = "temp-cleanup"
    enabled = true

    filters {
      prefix_match = ["tmp/"]
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = 7
      }
    }
  }
}

################################################################################
# Diagnostics
#
# Write and delete operations only. Read logging on a busy account is an
# ingestion cost with very little forensic value.
################################################################################

resource "azurerm_monitor_diagnostic_setting" "storage_blob" {
  name                       = "diag-storage-blob"
  target_resource_id         = "${azurerm_storage_account.this.id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }
}
