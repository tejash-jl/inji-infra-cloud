resource "azurerm_user_assigned_identity" "identity" {
  name                = "aks-identity-${var.env}"
  resource_group_name = var.resource_group.name
  location            = var.resource_group.location
}