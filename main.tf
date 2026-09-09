################################################################################
# Provider configuration, naming, tagging and the platform resource group.
#
# Everything in this configuration is deployed into a single resource group.
# AKS creates and manages its own node resource group separately; its name is
# set explicitly below so it is predictable rather than generated.
################################################################################

provider "azurerm" {
  # Subscription is supplied by ARM_SUBSCRIPTION_ID in CI. The variable exists
  # so a local operator can override it without exporting environment vars.
  subscription_id = var.subscription_id

  # Storage data-plane operations authenticate with Entra ID rather than
  # account keys.
  storage_use_azuread = true

  features {
    key_vault {
      # Purge protection is enabled on the vault, so a destroy leaves the vault
      # and its keys soft-deleted for the retention window. Do not attempt to
      # purge on destroy — it will fail and leave the apply in a broken state.
      purge_soft_delete_on_destroy       = false
      purge_soft_deleted_keys_on_destroy = false
      recover_soft_deleted_key_vaults    = true
      recover_soft_deleted_keys          = true
    }

    resource_group {
      prevent_deletion_if_contains_resources = true
    }

    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }
  }
}

provider "random" {}

################################################################################
# Data sources
################################################################################

data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}

################################################################################
# Naming
#
# Azure resource naming is inconsistent across services: some accept hyphens and
# mixed case, some are globally unique and lowercase-alphanumeric only. The
# locals below compute both forms once so no resource has to reinvent them.
################################################################################

resource "random_string" "suffix" {
  length  = 5
  special = false
  upper   = false
  numeric = true

  # The suffix is baked into globally unique names. Regenerating it would
  # rename the Key Vault and storage account, which forces replacement.
  keepers = {
    project     = var.project
    environment = var.environment
    location    = var.location
  }
}

locals {
  # Hyphenated form, used by resources that accept it: rg-, vnet-, aks- and so on.
  name_prefix = lower("${var.project}-${var.environment}-${var.location_short}")

  # Compact form for globally unique, alphanumeric-only names.
  name_compact = lower(replace(local.name_prefix, "-", ""))

  # Key Vault: 3-24 characters, alphanumerics and hyphens, must start with a letter.
  key_vault_name = substr("kv-${local.name_compact}-${random_string.suffix.result}", 0, 24)

  # Storage account: 3-24 characters, lowercase alphanumerics only.
  storage_account_name = substr("st${local.name_compact}${random_string.suffix.result}", 0, 24)

  # AKS node resource group. Set explicitly so support tooling can find it.
  node_resource_group = "rg-${local.name_prefix}-aks-nodes"

  common_tags = merge(
    {
      project             = var.project
      environment         = var.environment
      owner               = var.owner
      cost_center         = var.cost_center
      data_classification = var.data_classification
      criticality         = var.criticality
      managed_by          = "terraform"
      repository          = var.repository_url
    },
    var.additional_tags,
  )
}

################################################################################
# Resource group
################################################################################

resource "azurerm_resource_group" "this" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.common_tags
}
