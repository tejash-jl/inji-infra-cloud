output "aks_dataplane_subnet_id" {
  description = "The ID of the subnet"
  value       = azurerm_subnet.aks-data-plane.id
}

output "bastion_subnet_id" {
  description = "The ID of the subnet"
  value       = azurerm_subnet.bastion.id
}

output "api_server_subnet_id" {
  description = "The ID of the subnet"
  value       = azurerm_subnet.api-server.id
}

output "jumphost_subnet_id" {
  description = "The ID of the subnet"
  value       = azurerm_subnet.jumphost_subnet.id
}

output "jumphost_subnet_cidr_blocks" {
  description = "The CIDR blocks of the subnet"
  value       = azurerm_subnet.jumphost_subnet.address_prefixes
}

output "data_subnet_id" {
  description = "The ID of the data subnet"
  value       = azurerm_subnet.data_subnet.id
}

output "vpc_id" {
  description = "The ID of the vpc"
  value = azurerm_virtual_network.vpc.id
}


output "redis_subnet_id" {
  description = "The ID of the redis subnet"
  value       = azurerm_subnet.redis_subnet.id
}
