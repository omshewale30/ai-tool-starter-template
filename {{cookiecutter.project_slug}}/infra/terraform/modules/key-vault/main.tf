# Azure Key Vault with RBAC authorization. Readers (the app identity) get "Key Vault
# Secrets User"; writers (whoever runs Terraform, and the CD identity that writes
# database-url) get "Key Vault Secrets Officer". Owner/Contributor grant no access to
# secret contents, so the writer grants are what let Terraform seed secrets at all.
#
# New role assignments take minutes to reach Key Vault's data plane. `id` is only
# known after `rbac_propagation`, so secrets and Key Vault references created from it
# wait for the grants instead of failing with 403 on the first apply.

terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
    time = {
      source = "hashicorp/time"
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

variable "tenant_id" {
  type = string
}

variable "reader_principal_ids" {
  description = "Managed identities (object ids) granted Key Vault Secrets User."
  type        = map(string)
  default     = {}
}

variable "writer_principals" {
  description = "Principals granted Key Vault Secrets Officer, keyed by a stable label."
  type = map(object({
    object_id = string
    type      = optional(string) # User | ServicePrincipal | Group; null lets Azure infer it
  }))
  default = {}
}

variable "soft_delete_retention_days" {
  type    = number
  default = 7
}

variable "purge_protection_enabled" {
  description = "Irreversible once on; recommended for prod. Blocks purge for the retention period."
  type        = bool
  default     = false
}

variable "rbac_propagation_wait" {
  description = "How long to wait after granting roles before using the vault."
  type        = string
  default     = "90s"
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "azurerm_key_vault" "this" {
  name                          = var.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  tenant_id                     = var.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  soft_delete_retention_days    = var.soft_delete_retention_days
  purge_protection_enabled      = var.purge_protection_enabled
  public_network_access_enabled = true
  tags                          = var.tags
}

resource "azurerm_role_assignment" "reader" {
  for_each = var.reader_principal_ids

  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = each.value
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "writer" {
  for_each = var.writer_principals

  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = each.value.object_id
  principal_type       = each.value.type
}

resource "time_sleep" "rbac_propagation" {
  create_duration = var.rbac_propagation_wait

  triggers = {
    readers = join(",", sort(values(var.reader_principal_ids)))
    writers = join(",", sort([for p in values(var.writer_principals) : p.object_id]))
  }

  depends_on = [azurerm_role_assignment.reader, azurerm_role_assignment.writer]
}

output "id" {
  description = "Vault id, available once role assignments have had time to apply."
  value       = azurerm_key_vault.this.id
  depends_on  = [time_sleep.rbac_propagation]
}

output "name" {
  value = azurerm_key_vault.this.name
}

output "uri" {
  value = azurerm_key_vault.this.vault_uri
}
