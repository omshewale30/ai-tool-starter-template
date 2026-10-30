# Azure Container Registry, shared by every environment: CI publishes each image
# once and CD promotes the same digest (docs/adr/0005). Admin user is off; pulls use
# each environment's managed identity (AcrPull, granted by app-stack) and pushes use
# the CI/CD identity (granted here).

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

variable "sku" {
  description = "Basic is enough for a few images; Standard/Premium add throughput and retention."
  type        = string
  default     = "Basic"
}

variable "pusher_principal_ids" {
  description = "Object ids that build and push images (the CI/CD identity)."
  type        = set(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "azurerm_container_registry" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku
  admin_enabled       = false
  tags                = var.tags
}

resource "azurerm_role_assignment" "push" {
  for_each = var.pusher_principal_ids

  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPush"
  principal_id         = each.value
  principal_type       = "ServicePrincipal"
}

# scripts/publish.sh runs `az acr build` (an ACR Task: registries/scheduleRun/action)
# and `az acr repository show`, which resolve the registry through ARM. AcrPush grants
# neither, so the CI/CD identity also needs Contributor, on this registry only.
resource "azurerm_role_assignment" "build" {
  for_each = var.pusher_principal_ids

  scope                = azurerm_container_registry.this.id
  role_definition_name = "Contributor"
  principal_id         = each.value
  principal_type       = "ServicePrincipal"
}

output "id" {
  value = azurerm_container_registry.this.id
}

output "name" {
  value = azurerm_container_registry.this.name
}

output "login_server" {
  value = azurerm_container_registry.this.login_server
}
