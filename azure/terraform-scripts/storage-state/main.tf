
resource "azurerm_resource_group" "tfstate" {
  name     = "tfstate-rg-${var.env}"
  location = var.region
}

resource "azurerm_storage_account" "tfstate" {
  name                     = "injistate${var.env}"
  resource_group_name      = azurerm_resource_group.tfstate.name
  location                 = azurerm_resource_group.tfstate.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = {
    environment = var.env
  }
}

resource "azurerm_storage_container" "tfstate_container" {
  name                  = "tfstate${var.env}"
  storage_account_name  = azurerm_storage_account.tfstate.name
  container_access_type = "private"
}
