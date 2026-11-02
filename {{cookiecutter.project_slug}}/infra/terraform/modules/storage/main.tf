# Storage account + uploads container. Shared keys are disabled: the app uses its
# managed identity ("Storage Blob Data Contributor"), and Terraform manages
# containers through the management plane.

terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
  }
}

variable "name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "container_name" {
  type    = string
  default = "uploads"
}

variable "replication_type" {
  description = "LRS for dev; ZRS or GRS for prod."
  type        = string
  default     = "LRS"
}

variable "contributor_principal_ids" {
  description = "Managed identities (object ids) granted Storage Blob Data Contributor."
  type        = map(string)
  default     = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "azurerm_storage_account" "this" {
  name                            = var.name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = var.replication_type
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  tags                            = var.tags
}

resource "azurerm_storage_container" "uploads" {
  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "contributor" {
  for_each = var.contributor_principal_ids

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
  principal_type       = "ServicePrincipal"
}

output "id" {
  value = azurerm_storage_account.this.id
}

output "name" {
  value = azurerm_storage_account.this.name
}

output "blob_endpoint" {
  value = azurerm_storage_account.this.primary_blob_endpoint
}

output "container_name" {
  value = azurerm_storage_container.uploads.name
}
