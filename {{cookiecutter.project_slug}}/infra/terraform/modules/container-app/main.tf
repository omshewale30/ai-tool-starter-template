# Generic Azure Container App used for both the web app and the API.
#
# Authenticates to ACR and Key Vault with a user-assigned managed identity. Single
# revision mode and min_replicas >= 1 are what scripts/cd.sh's health gate requires.
#
# Infra creates, CD owns: Terraform sets the bootstrap image and the initial env;
# scripts/cd.sh then replaces both on every release (`az containerapp update --image
# --replace-env-vars`), so they are ignored here. Everything else (identity, registry,
# ingress, probes, Key Vault secrets, scale) stays Terraform's.

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

variable "container_app_environment_id" {
  type = string
}

variable "identity_id" {
  description = "User-assigned managed identity resource id."
  type        = string
}

variable "registry_server" {
  description = "ACR login server, e.g. myacr.azurecr.io."
  type        = string
}

variable "image" {
  description = "Bootstrap image; scripts/cd.sh replaces it with the published digest."
  type        = string
  default     = "mcr.microsoft.com/k8se/quickstart:latest"
}

variable "target_port" {
  type = number
}

variable "external" {
  description = "Expose publicly (true) or only within the Container Apps environment (false)."
  type        = bool
}

variable "env" {
  description = "Initial plain environment variables (name => value)."
  type        = map(string)
  default     = {}
}

variable "key_vault_secrets" {
  description = "Container app secret name => versionless Key Vault secret id."
  type        = map(string)
  default     = {}
}

variable "secret_env" {
  description = "Initial env vars sourced from secrets (env name => secret name)."
  type        = map(string)
  default     = {}
}

variable "liveness_path" {
  type = string
}

variable "readiness_path" {
  type = string
}

variable "cpu" {
  type    = number
  default = 0.5
}

variable "memory" {
  type    = string
  default = "1Gi"
}

variable "min_replicas" {
  type    = number
  default = 1

  validation {
    condition     = var.min_replicas >= 1
    error_message = "min_replicas must be at least 1 (scripts/cd.sh health-checks a running replica)."
  }
}

variable "max_replicas" {
  type    = number
  default = 3
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "azurerm_container_app" "this" {
  name                         = var.name
  resource_group_name          = var.resource_group_name
  container_app_environment_id = var.container_app_environment_id
  revision_mode                = "Single"
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [var.identity_id]
  }

  registry {
    server   = var.registry_server
    identity = var.identity_id
  }

  dynamic "secret" {
    for_each = var.key_vault_secrets
    content {
      name                = secret.key
      key_vault_secret_id = secret.value
      identity            = var.identity_id
    }
  }

  ingress {
    external_enabled           = var.external
    target_port                = var.target_port
    transport                  = "auto"
    allow_insecure_connections = false

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    container {
      name   = var.name
      image  = var.image
      cpu    = var.cpu
      memory = var.memory

      dynamic "env" {
        for_each = var.env
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = var.secret_env
        content {
          name        = env.key
          secret_name = env.value
        }
      }

      liveness_probe {
        transport               = "HTTP"
        port                    = var.target_port
        path                    = var.liveness_path
        initial_delay           = 10
        interval_seconds        = 30
        failure_count_threshold = 3
      }

      readiness_probe {
        transport               = "HTTP"
        port                    = var.target_port
        path                    = var.readiness_path
        initial_delay           = 5
        interval_seconds        = 10
        failure_count_threshold = 3
      }
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].container[0].image,
      template[0].container[0].env,
    ]
  }
}

output "name" {
  value = azurerm_container_app.this.name
}

output "fqdn" {
  description = "Ingress FQDN; for internal ingress this is <app>.internal.<environment domain>."
  value       = azurerm_container_app.this.ingress[0].fqdn
}
