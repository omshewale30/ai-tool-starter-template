# Resources every environment shares. Today: the container registry, so CI publishes
# each image once and CD promotes the same digest to dev, then prod. Apply this root
# before any envs/<env>.

data "azurerm_client_config" "current" {}

module "names" {
  source = "../../modules/naming"

  prefix          = var.prefix
  environment     = "shared"
  subscription_id = data.azurerm_client_config.current.subscription_id
}

resource "azurerm_resource_group" "shared" {
  name     = module.names.resource_group
  location = var.location
  tags     = merge(var.tags, { environment = "shared", managed_by = "terraform" })
}

module "registry" {
  source = "../../modules/registry"

  name                 = module.names.registry
  resource_group_name  = azurerm_resource_group.shared.name
  location             = var.location
  sku                  = var.registry_sku
  pusher_principal_ids = var.deploy_principal_id == null ? [] : [var.deploy_principal_id]
  tags                 = azurerm_resource_group.shared.tags
}
