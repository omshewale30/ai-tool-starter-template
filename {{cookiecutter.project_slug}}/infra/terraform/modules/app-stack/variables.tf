variable "prefix" {
  description = "Resource name prefix (2-12 lowercase letters/digits)."
  type        = string
}

variable "environment" {
  description = "Environment name used in resource names and tags (dev, prod, ...)."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "tags" {
  description = "Tags merged onto every resource."
  type        = map(string)
  default     = {}
}

variable "registry" {
  description = "The shared container registry (envs/shared) the apps pull from."
  type = object({
    id           = string
    login_server = string
  })
}

variable "deploy_principal_id" {
  description = <<-EOT
    Object id of the CI/CD service principal (GitHub OIDC). Granted Contributor on the
    resource group (container app updates) and Key Vault Secrets Officer (database-url).
    Null to skip.
  EOT
  type        = string
  default     = null
}

variable "operator_principal_ids" {
  description = <<-EOT
    People who run Terraform (label => Entra object id; an Entra group is best).
    Granted Key Vault Secrets Officer. Must include whoever applies. Empty: the caller.
  EOT
  type        = map(string)
  default     = {}
  nullable    = false
}

# ---- Entra (initial web env; CD owns it after the first deploy) ----

variable "entra_tenant_id" {
  type = string
}

variable "entra_web_client_id" {
  description = "Client id of the web (SPA) app registration."
  type        = string
}

variable "entra_api_scope" {
  description = "Delegated API scope the web requests, e.g. api://<api client id>/access_as_user."
  type        = string
}

# ---- Sizing: dev defaults, raise in envs/prod/terraform.tfvars ----

variable "log_retention_days" {
  type     = number
  default  = 30
  nullable = false
}

variable "storage_replication_type" {
  type     = string
  default  = "LRS"
  nullable = false
}

variable "key_vault_purge_protection" {
  type     = bool
  default  = false
  nullable = false
}

variable "postgres_sku_name" {
  type     = string
  default  = "B_Standard_B1ms"
  nullable = false
}

variable "postgres_storage_mb" {
  type     = number
  default  = 32768
  nullable = false
}

variable "postgres_backup_retention_days" {
  type     = number
  default  = 7
  nullable = false
}

variable "postgres_geo_redundant_backup" {
  type     = bool
  default  = false
  nullable = false
}

variable "postgres_password_version" {
  description = <<-EOT
    Bump to rotate the Postgres admin password: Terraform generates a new one, writes
    it to the server and to Key Vault (postgres-admin-password, database-url). Then
    update the GitHub DATABASE_URL secret, which CD writes over database-url.
  EOT
  type        = number
  default     = 1
  nullable    = false
}

variable "apps" {
  description = "Per-app scale and size."
  type = object({
    api = optional(object({
      cpu          = optional(number, 0.5)
      memory       = optional(string, "1Gi")
      min_replicas = optional(number, 1)
      max_replicas = optional(number, 3)
    }), {})
    web = optional(object({
      cpu          = optional(number, 0.5)
      memory       = optional(string, "1Gi")
      min_replicas = optional(number, 1)
      max_replicas = optional(number, 3)
    }), {})
  })
  default  = {}
  nullable = false
}
