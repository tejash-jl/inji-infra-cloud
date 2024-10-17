output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "lb_ip" {
  value = module.aks.lb_ip
}
