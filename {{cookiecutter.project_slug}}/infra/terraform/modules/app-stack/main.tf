# One complete environment of the app: resource group, identity, observability,
# Key Vault, storage, Postgres, the Container Apps environment and both apps.
# envs/<env> call this module once with that environment's settings, so environments
# differ only in their tfvars. The registry is shared and lives in envs/shared.

terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
    random = {
      source = "hashicorp/random"
    }
    time = {
      source = "hashicorp/time"
    }
  }
}

data "azurerm_client_config" "current" {}

module "names" {
  source = "../naming"

  prefix          = var.prefix
  environment     = var.environment
  subscription_id = data.azurerm_client_config.current.subscription_id
}

locals {
  tags = merge(var.tags, {
    environment = var.environment
    managed_by  = "terraform"
  })
  deploy_principal = var.deploy_principal_id == null ? {} : { deploy = var.deploy_principal_id }
  # People who run Terraform seed and read secrets. Without an explicit list that is
  # just the caller, which changes hands when a teammate applies.
  operators = length(var.operator_principal_ids) > 0 ? var.operator_principal_ids : {
    terraform = data.azurerm_client_config.current.object_id
  }
}

resource "azurerm_resource_group" "this" {
  name     = module.names.resource_group
  location = var.location
  tags     = local.tags
}

module "identity" {
  source = "../identity"

  name                = module.names.identity
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  tags                = local.tags
}

module "observability" {
  source = "../observability"

  log_analytics_name  = module.names.log_analytics
  app_insights_name   = module.names.app_insights
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  retention_in_days   = var.log_retention_days
  tags                = local.tags
}

module "key_vault" {
  source = "../key-vault"

  name                     = module.names.key_vault
  resource_group_name      = azurerm_resource_group.this.name
  location                 = var.location
  tenant_id                = data.azurerm_client_config.current.tenant_id
  purge_protection_enabled = var.key_vault_purge_protection
  tags                     = local.tags

  reader_principal_ids = { app = module.identity.principal_id }
  # Operators seed secrets; the CD identity keeps database-url current.
  writer_principals = merge(
    { for k, id in local.operators : "operator-${k}" => { object_id = id } },
    { for k, id in local.deploy_principal : k => { object_id = id, type = "ServicePrincipal" } },
  )
}

module "storage" {
  source = "../storage"

  name                      = module.names.storage_account
  resource_group_name       = azurerm_resource_group.this.name
  location                  = var.location
  replication_type          = var.storage_replication_type
  contributor_principal_ids = { app = module.identity.principal_id }
  tags                      = local.tags
}

module "postgres" {
  source = "../postgres"

  name                           = module.names.postgres
  resource_group_name            = azurerm_resource_group.this.name
  location                       = var.location
  administrator_login            = "${var.prefix}admin"
  administrator_password         = ephemeral.azurerm_key_vault_secret.postgres_admin_password.value
  administrator_password_version = var.postgres_password_version
  sku_name                       = var.postgres_sku_name
  storage_mb                     = var.postgres_storage_mb
  backup_retention_days          = var.postgres_backup_retention_days
  geo_redundant_backup_enabled   = var.postgres_geo_redundant_backup
  tags                           = local.tags
}

module "container_apps_env" {
  source = "../container-apps-env"

  name                       = module.names.container_apps_env
  resource_group_name        = azurerm_resource_group.this.name
  location                   = var.location
  log_analytics_workspace_id = module.observability.log_analytics_id
  tags                       = local.tags
}

# ---- Access for the app identity and the CD identity ----

resource "azurerm_role_assignment" "acr_pull" {
  scope                = var.registry.id
  role_definition_name = "AcrPull"
  principal_id         = module.identity.principal_id
  principal_type       = "ServicePrincipal"
}

# The CD workflow updates container apps and reads their config.
resource "azurerm_role_assignment" "deploy_contributor" {
  for_each = local.deploy_principal

  scope                = azurerm_resource_group.this.id
  role_definition_name = "Contributor"
  principal_id         = each.value
  principal_type       = "ServicePrincipal"
}

# Container Apps checks registry access when it creates a revision; give the AcrPull
# grant time to apply (Key Vault grants wait inside the key-vault module).
resource "time_sleep" "acr_pull_propagation" {
  create_duration = "60s"
  triggers = {
    assignment = azurerm_role_assignment.acr_pull.id
  }
}
