output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "identity" {
  description = "The apps' managed identity (request Azure OpenAI access for principal_id)."
  value = {
    id           = module.identity.id
    principal_id = module.identity.principal_id
    client_id    = module.identity.client_id
  }
}

output "key_vault_name" {
  value = module.key_vault.name
}

output "key_vault_uri" {
  value = module.key_vault.uri
}

output "storage_account_name" {
  value = module.storage.name
}

output "storage_account_id" {
  value = module.storage.id
}

output "storage_blob_endpoint" {
  value = module.storage.blob_endpoint
}

output "postgres" {
  value = {
    server_fqdn         = module.postgres.fqdn
    database_name       = module.postgres.database_name
    administrator_login = module.postgres.administrator_login
  }
}

output "api_app_name" {
  value = module.api.name
}

output "api_fqdn" {
  value = module.api.fqdn
}

output "web_app_name" {
  value = module.web.name
}

output "web_url" {
  value = "https://${module.web.fqdn}"
}
