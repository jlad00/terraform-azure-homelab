output "resource_group_name" {
  description = "Name of the primary resource group"
  value       = azurerm_resource_group.main.name
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

output "vnet_id" {
  description = "Virtual network resource ID"
  value       = module.networking.vnet_id
}

output "subnet_ids" {
  description = "Map of subnet IDs"
  value       = module.networking.subnet_ids
}

output "mgmt_vnet_id" {
  description = "Management VNet resource ID"
  value       = module.networking_mgmt.vnet_id
}

output "mgmt_subnet_ids" {
  description = "Management subnet IDs"
  value       = module.networking_mgmt.subnet_ids
}