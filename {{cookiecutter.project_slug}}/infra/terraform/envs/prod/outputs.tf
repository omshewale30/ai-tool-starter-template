# Read by infra/scripts/print-github-settings.sh (terraform output -json).

output "resource_group_name" {
  value = module.app.resource_group_name
}

output "identity" {
  value = module.app.identity
}

output "key_vault_name" {
  value = module.app.key_vault_name
}

output "storage_account_id" {
  value = module.app.storage_account_id
}

output "storage_blob_endpoint" {
  value = module.app.storage_blob_endpoint
}

output "postgres" {
  value = module.app.postgres
}

output "api_app_name" {
  value = module.app.api_app_name
}

output "web_app_name" {
  value = module.app.web_app_name
}

output "web_url" {
  value = module.app.web_url
}
