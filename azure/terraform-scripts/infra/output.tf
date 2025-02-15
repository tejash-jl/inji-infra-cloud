output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "lb_ip" {
  value = module.aks.lb_ip
}

output "bastion_vm_public_ip" {
  value = module.bastion.bastion_vm_public_ip
}
