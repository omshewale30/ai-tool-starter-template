# Key Vault secrets infra owns or seeds. No secret value is stored in plan or state
# except the App Insights connection string (already an attribute of App Insights).
#
#   appinsights-connection-string  owned by Terraform.
#   postgres-admin-password        generated once (ephemeral, write-only); rotated by
#                                  bumping postgres_password_version.
#   database-url                   seeded so the API's Key Vault reference resolves on
#                                  creation; scripts/cd.sh owns it afterwards and writes
#                                  it from the GitHub DATABASE_URL secret on every deploy.

resource "azurerm_key_vault_secret" "appinsights_connection_string" {
  name         = "appinsights-connection-string"
  key_vault_id = module.key_vault.id
  value        = module.observability.app_insights_connection_string
}

# A fresh value every run, but only written when postgres_password_version changes.
ephemeral "random_password" "postgres" {
  length  = 32
  special = false # embedded in DATABASE_URL, so keep it URL-safe
}

resource "azurerm_key_vault_secret" "postgres_admin_password" {
  name             = "postgres-admin-password"
  key_vault_id     = module.key_vault.id
  value_wo         = ephemeral.random_password.postgres.result
  value_wo_version = var.postgres_password_version
}

# Read back what Key Vault holds, so every run feeds the server the stored password.
ephemeral "azurerm_key_vault_secret" "postgres_admin_password" {
  name         = azurerm_key_vault_secret.postgres_admin_password.name
  key_vault_id = module.key_vault.id
}

resource "azurerm_key_vault_secret" "database_url" {
  name         = "database-url"
  key_vault_id = module.key_vault.id
  value_wo = format(
    "postgresql+psycopg://%s:%s@%s:5432/%s?sslmode=require",
    module.postgres.administrator_login,
    ephemeral.azurerm_key_vault_secret.postgres_admin_password.value,
    module.postgres.fqdn,
    module.postgres.database_name,
  )
  value_wo_version = var.postgres_password_version
}
