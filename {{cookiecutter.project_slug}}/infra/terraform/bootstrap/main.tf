# Run once per subscription, before anything else. Creates the storage account that
# holds every other root's Terraform state, and registers the resource providers the
# stack needs (azurerm 5.x registers none by itself).
#
# This root keeps its own state locally (git-ignored): it is three resources, and
# `terraform import` recreates the state if it is lost. Afterwards:
#   terraform output -raw backend_config > ../backend.hcl   # commit it

terraform {
  required_version = ">= 1.11, < 2.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.11"
    }
  }
}

provider "azurerm" {
  features {}
  storage_use_azuread             = true
  resource_provider_registrations = "none"
  resource_providers_to_register = [
    "Microsoft.App",
    "Microsoft.ContainerRegistry",
    "Microsoft.DBforPostgreSQL",
    "Microsoft.Insights",
    "Microsoft.KeyVault",
    "Microsoft.ManagedIdentity",
    "Microsoft.OperationalInsights",
    "Microsoft.Search",
    "Microsoft.Storage",
  ]
}

data "azurerm_client_config" "current" {}

module "names" {
  source = "../modules/naming"

  prefix          = var.prefix
  environment     = "tfstate"
  subscription_id = data.azurerm_client_config.current.subscription_id
}

resource "azurerm_resource_group" "state" {
  name     = module.names.resource_group
  location = var.location
  tags     = merge(var.tags, { managed_by = "terraform" })
}

resource "azurerm_storage_account" "state" {
  name                            = module.names.state_storage_account
  resource_group_name             = azurerm_resource_group.state.name
  location                        = azurerm_resource_group.state.location
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = "ZRS"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false # Entra ID only (backend use_azuread_auth)
  default_to_oauth_authentication = true
  tags                            = azurerm_resource_group.state.tags

  # State history: recover from a bad apply or an accidental delete.
  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_storage_container" "state" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
}

# Owner/Contributor grant no blob data access; whoever runs Terraform needs this.
resource "azurerm_role_assignment" "state_contributor" {
  for_each = length(var.state_contributor_principal_ids) > 0 ? var.state_contributor_principal_ids : {
    terraform = data.azurerm_client_config.current.object_id
  }

  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
}
