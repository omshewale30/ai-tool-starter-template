# Values are in terraform.tfvars. Sizing left null takes the default in
# modules/app-stack/variables.tf (dev-sized), so there is one place for defaults.

variable "prefix" {
  type = string
}

variable "environment" {
  type = string
}

variable "location" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "deploy_principal_id" {
  type    = string
  default = null
}

variable "operator_principal_ids" {
  type    = map(string)
  default = null
}

variable "entra_tenant_id" {
  type = string
}

variable "entra_web_client_id" {
  type = string
}

variable "entra_api_scope" {
  type = string
}

variable "log_retention_days" {
  type    = any
  default = null
}

variable "storage_replication_type" {
  type    = any
  default = null
}

variable "key_vault_purge_protection" {
  type    = any
  default = null
}

variable "postgres_sku_name" {
  type    = any
  default = null
}

variable "postgres_storage_mb" {
  type    = any
  default = null
}

variable "postgres_backup_retention_days" {
  type    = any
  default = null
}

variable "postgres_geo_redundant_backup" {
  type    = any
  default = null
}

variable "postgres_password_version" {
  type    = any
  default = null
}

variable "apps" {
  type    = any
  default = null
}
