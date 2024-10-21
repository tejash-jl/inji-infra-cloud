
output "lb_ip" {
  description = "The LoadBalancer IP"
  value = azurerm_public_ip.lb_ip.ip_address
}