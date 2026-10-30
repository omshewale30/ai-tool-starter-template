# Optional RAG (Azure AI Search). Generated projects without RAG don't have this file.

variable "search_sku" {
  type    = string
  default = "basic"
}

module "search" {
  source = "../search"

  name                = module.names.search
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  sku                 = var.search_sku
  storage_account_id  = module.storage.id
  reader_principal_ids = {
    app = module.identity.principal_id
  }
  tags = local.tags
}

output "search" {
  value = {
    name                     = module.search.name
    endpoint                 = module.search.endpoint
    principal_id             = module.search.principal_id
    documents_container_name = module.search.documents_container_name
  }
}
