# Azure AI Search for RAG, built around a Blob indexer:
#   - a `documents` container in the app's storage account (drop files there);
#   - the search service's system-assigned identity, granted Storage Blob Data Reader
#     on the account so the indexer reads documents keylessly;
#   - the app's managed identity granted Search Index Data Reader to query.
# The index, data source, skillset and indexer are data-plane objects:
# infra/scripts/setup-search-index.sh creates them.
#
# Hand-off (not done here, because UNC owns the resource): the search service's
# identity also needs "Cognitive Services OpenAI User" on UNC's Azure OpenAI resource,
# to embed chunks and queries. See docs/rag.md.

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

variable "sku" {
  description = "basic supports vector search and is enough for a prototype."
  type        = string
  default     = "basic"
}

variable "storage_account_id" {
  description = "Storage account that holds the documents container."
  type        = string
}

variable "documents_container_name" {
  type    = string
  default = "documents"
}

variable "reader_principal_ids" {
  description = "Managed identities (object ids) granted Search Index Data Reader."
  type        = map(string)
  default     = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "azurerm_search_service" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku
  replica_count       = 1
  partition_count     = 1
  hosting_mode        = "default"
  tags                = var.tags

  # Entra ID (RBAC) and keys both accepted; the app and indexer use Entra only.
  local_authentication_enabled = true
  authentication_failure_mode  = "http401WithBearerChallenge"

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_storage_container" "documents" {
  name                  = var.documents_container_name
  storage_account_id    = var.storage_account_id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "index_reader" {
  for_each = var.reader_principal_ids

  scope                = azurerm_search_service.this.id
  role_definition_name = "Search Index Data Reader"
  principal_id         = each.value
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "indexer_blob_reader" {
  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_search_service.this.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

output "name" {
  value = azurerm_search_service.this.name
}

output "endpoint" {
  value = "https://${azurerm_search_service.this.name}.search.windows.net"
}

output "principal_id" {
  value = azurerm_search_service.this.identity[0].principal_id
}

output "documents_container_name" {
  value = azurerm_storage_container.documents.name
}
