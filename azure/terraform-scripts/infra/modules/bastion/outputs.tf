output "bastion_id" {
  value = azurerm_linux_virtual_machine.bastion_vm.id
}

output "bastion_vm_public_ip" {
  value = azurerm_public_ip.bastion_vm_pip.ip_address
}