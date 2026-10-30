# The two container apps. Terraform creates them on a placeholder image; from the
# first CD run on, scripts/cd.sh owns their image and env (deploy/env-contract.json),
# and the container-app module ignores both.

# Internal ingress only. Browsers reach it through the web app's /api/* forwarder.
module "api" {
  source = "../container-app"

  name                         = module.names.api_app
  resource_group_name          = azurerm_resource_group.this.name
  container_app_environment_id = module.container_apps_env.id
  identity_id                  = module.identity.id
  registry_server              = var.registry.login_server
  target_port                  = 8000
  external                     = false
  liveness_path                = "/health/live"
  readiness_path               = "/health/ready"
  cpu                          = var.apps.api.cpu
  memory                       = var.apps.api.memory
  min_replicas                 = var.apps.api.min_replicas
  max_replicas                 = var.apps.api.max_replicas
  tags                         = local.tags

  key_vault_secrets = {
    "database-url"                  = azurerm_key_vault_secret.database_url.versionless_id
    "appinsights-connection-string" = azurerm_key_vault_secret.appinsights_connection_string.versionless_id
  }
  # Infra-owned (deploy/env-contract.json `infra`): which identity the SDKs use.
  env = {
    AZURE_CLIENT_ID = module.identity.client_id
  }
  secret_env = {
    DATABASE_URL                          = "database-url"
    APPLICATIONINSIGHTS_CONNECTION_STRING = "appinsights-connection-string"
  }

  depends_on = [time_sleep.acr_pull_propagation]
}

# The only public endpoint: serves Next.js and forwards /api/* to the API's internal
# FQDN (BACKEND_ORIGIN), which CD re-derives the same way on every deploy.
module "web" {
  source = "../container-app"

  name                         = module.names.web_app
  resource_group_name          = azurerm_resource_group.this.name
  container_app_environment_id = module.container_apps_env.id
  identity_id                  = module.identity.id
  registry_server              = var.registry.login_server
  target_port                  = 3000
  external                     = true
  liveness_path                = "/healthz"
  readiness_path               = "/healthz"
  cpu                          = var.apps.web.cpu
  memory                       = var.apps.web.memory
  min_replicas                 = var.apps.web.min_replicas
  max_replicas                 = var.apps.web.max_replicas
  tags                         = local.tags

  env = {
    BACKEND_ORIGIN  = "https://${module.api.fqdn}"
    ENTRA_CLIENT_ID = var.entra_web_client_id
    ENTRA_TENANT_ID = var.entra_tenant_id
    ENTRA_API_SCOPE = var.entra_api_scope
  }

  depends_on = [time_sleep.acr_pull_propagation]
}
