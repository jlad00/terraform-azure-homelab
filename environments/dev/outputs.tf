output "resource_group_name" {
  description = "Name of the primary resource group"
  value       = azurerm_resource_group.primary.name
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.primary.location
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

output "environment_check" {
  value = "Environment: ${var.environment} | RG: ${local.resource_group_name}"
}

output "vm_name" {
  value = module.app_vm.vm_name
}

output "vm_private_ip" {
  value = module.app_vm.private_ip
}

output "vm_principal_id" {
  value = module.app_vm.principal_id
}