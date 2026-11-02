output "resource_group_name" {
  value = azurerm_resource_group.shared.name
}

output "registry_name" {
  description = "The ACR_NAME repository variable."
  value       = module.registry.name
}

output "registry_login_server" {
  value = module.registry.login_server
}
