################################################################################
# Provider and backend requirements
#
# Provider versions are pinned exactly. The AzureRM 4.x line renames arguments
# between minor releases, so an unpinned upgrade changes plan output with no
# change to this configuration. Upgrades are a deliberate, reviewed edit to this
# file followed by `terraform init -upgrade`.
#
# .terraform.lock.hcl is committed and carries checksums for both linux_amd64
# (the CI runner) and windows_amd64 (workstations). After any provider change,
# regenerate it for both platforms:
#
#   terraform providers lock -platform=linux_amd64 -platform=windows_amd64
################################################################################

terraform {
  required_version = ">= 1.15.0, < 2.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.81.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "3.9.0"
    }
  }

  # Remote state lives in the bootstrap storage account created outside this
  # configuration. Authentication is Entra ID + workload identity federation:
  # there is no storage account key and no client secret anywhere in the repo.
  #
  # OIDC is enabled in CI via ARM_USE_OIDC; locally this falls through to Azure CLI.
  backend "azurerm" {
    resource_group_name  = "rg-tfstate-demo"
    storage_account_name = "sttfstate19500"
    container_name       = "tfstate"
    key                  = "prod.tfstate"
    use_azuread_auth     = true
  }
}
