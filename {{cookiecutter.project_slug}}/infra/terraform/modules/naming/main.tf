# Resource names, in one place, so every root derives the same name for the same
# thing (env roots look up the shared registry by the name this module gives it).
#
# Globally unique names (Key Vault, storage, registry, Postgres, Search) carry a short
# suffix hashed from the subscription, prefix and environment: stable across applies
# and machines, unlike random_string, and unique enough across tenants.

variable "prefix" {
  description = "Resource name prefix (2-12 lowercase letters/digits)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,11}$", var.prefix))
    error_message = "prefix must be 2-12 lowercase letters/digits, starting with a letter."
  }
}

variable "environment" {
  description = "Environment name, e.g. dev, prod, shared."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,7}$", var.environment))
    error_message = "environment must be 2-8 lowercase letters/digits, starting with a letter."
  }
}

variable "subscription_id" {
  description = "Subscription the resources live in (feeds the uniqueness suffix)."
  type        = string
}

locals {
  base    = "${var.prefix}-${var.environment}"
  compact = "${var.prefix}${var.environment}"
  suffix  = substr(sha1("${var.subscription_id}/${local.base}"), 0, 6)
}

output "suffix" {
  value = local.suffix
}

output "resource_group" {
  value = "rg-${local.base}"
}

output "identity" {
  value = "id-${local.base}"
}

output "log_analytics" {
  value = "log-${local.base}"
}

output "app_insights" {
  value = "appi-${local.base}"
}

output "container_apps_env" {
  value = "cae-${local.base}"
}

output "api_app" {
  value = "ca-${local.base}-api"
}

output "web_app" {
  value = "ca-${local.base}-web"
}

output "key_vault" {
  value = substr("kv${local.compact}${local.suffix}", 0, 24)
}

output "storage_account" {
  value = substr("st${local.compact}${local.suffix}", 0, 24)
}

output "registry" {
  value = substr("acr${local.compact}${local.suffix}", 0, 50)
}

output "postgres" {
  value = "pg-${local.base}-${local.suffix}"
}

output "search" {
  value = "srch-${local.base}-${local.suffix}"
}

output "state_storage_account" {
  value = "st${var.prefix}tf${local.suffix}"
}
