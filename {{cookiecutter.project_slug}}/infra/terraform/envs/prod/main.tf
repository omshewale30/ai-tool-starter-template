# One environment. Everything it contains is modules/app-stack; this root only
# chooses settings (terraform.tfvars) and where the state lives (versions.tf).

data "azurerm_client_config" "current" {}

# The registry lives in envs/shared; derive its name the same way that root does.
module "shared_names" {
  source = "../../modules/naming"

  prefix          = var.prefix
  environment     = "shared"
  subscription_id = data.azurerm_client_config.current.subscription_id
}

data "azurerm_container_registry" "shared" {
  name                = module.shared_names.registry
  resource_group_name = module.shared_names.resource_group
}

module "app" {
  source = "../../modules/app-stack"

  prefix                 = var.prefix
  environment            = var.environment
  location               = var.location
  tags                   = var.tags
  deploy_principal_id    = var.deploy_principal_id
  operator_principal_ids = var.operator_principal_ids

  registry = {
    id           = data.azurerm_container_registry.shared.id
    login_server = data.azurerm_container_registry.shared.login_server
  }

  entra_tenant_id     = var.entra_tenant_id
  entra_web_client_id = var.entra_web_client_id
  entra_api_scope     = var.entra_api_scope

  log_retention_days             = var.log_retention_days
  storage_replication_type       = var.storage_replication_type
  key_vault_purge_protection     = var.key_vault_purge_protection
  postgres_sku_name              = var.postgres_sku_name
  postgres_storage_mb            = var.postgres_storage_mb
  postgres_backup_retention_days = var.postgres_backup_retention_days
  postgres_geo_redundant_backup  = var.postgres_geo_redundant_backup
  postgres_password_version      = var.postgres_password_version
  apps                           = var.apps
}
