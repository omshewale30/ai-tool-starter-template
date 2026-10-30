# Azure Database for PostgreSQL Flexible Server + the application database.
#
# The admin password is a write-only argument fed from an ephemeral value, so it never
# reaches plan or state. Terraform cannot diff it: bump `administrator_password_version`
# to send a new one. The app gets a full DATABASE_URL through the Key Vault secret
# `database-url` (app-stack seeds it; scripts/cd.sh owns it afterwards).

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

variable "administrator_login" {
  type = string
}

variable "administrator_password" {
  description = "URL-safe (it is embedded in DATABASE_URL). Only read when the version changes."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "administrator_password_version" {
  type = number
}

variable "database_name" {
  type    = string
  default = "appdb"
}

variable "postgres_version" {
  type    = string
  default = "16"
}

variable "sku_name" {
  description = "B_Standard_B1ms suits a prototype; use a General Purpose SKU for production load."
  type        = string
  default     = "B_Standard_B1ms"
}

variable "storage_mb" {
  type    = number
  default = 32768
}

variable "backup_retention_days" {
  type    = number
  default = 7
}

variable "geo_redundant_backup_enabled" {
  type    = bool
  default = false
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "azurerm_postgresql_flexible_server" "this" {
  name                              = var.name
  resource_group_name               = var.resource_group_name
  location                          = var.location
  version                           = var.postgres_version
  sku_name                          = var.sku_name
  storage_mb                        = var.storage_mb
  backup_retention_days             = var.backup_retention_days
  geo_redundant_backup_enabled      = var.geo_redundant_backup_enabled
  administrator_login               = var.administrator_login
  administrator_password_wo         = var.administrator_password
  administrator_password_wo_version = var.administrator_password_version
  public_network_access_enabled     = true
  tags                              = var.tags

  lifecycle {
    # Azure picks an availability zone when none is given; don't fight it.
    ignore_changes = [zone]
  }
}

resource "azurerm_postgresql_flexible_server_database" "app" {
  name      = var.database_name
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# Allowlist pgvector so a migration can `CREATE EXTENSION vector` if a tool stores
# embeddings in Postgres. Flexible Server rejects unlisted extensions.
resource "azurerm_postgresql_flexible_server_configuration" "extensions" {
  name      = "azure.extensions"
  server_id = azurerm_postgresql_flexible_server.this.id
  value     = "VECTOR"
}

# Lets Azure services (the Container Apps environment's outbound IPs) connect. This
# admits any Azure-hosted client, so the password is the real control; use VNet
# integration + private access when a tool handles sensitive data.
resource "azurerm_postgresql_flexible_server_firewall_rule" "azure_services" {
  name             = "AllowAllAzureIps"
  server_id        = azurerm_postgresql_flexible_server.this.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

output "name" {
  value = azurerm_postgresql_flexible_server.this.name
}

output "fqdn" {
  value = azurerm_postgresql_flexible_server.this.fqdn
}

output "database_name" {
  value = azurerm_postgresql_flexible_server_database.app.name
}

output "administrator_login" {
  value = azurerm_postgresql_flexible_server.this.administrator_login
}
