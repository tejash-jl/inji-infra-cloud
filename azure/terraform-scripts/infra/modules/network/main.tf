resource "azurerm_virtual_network" "vpc" {
  name                = "inji-vnet-${var.env}"
  address_space       = ["10.1.0.0/22"]
  location            = var.resource_group.location
  resource_group_name = var.resource_group.name
}
// 10.1.0.0 - 10.1.3.255
resource "azurerm_subnet" "aks-data-plane" {
  name                 = "aks-data-plane-${var.env}"
  resource_group_name  = var.resource_group.name
  virtual_network_name = azurerm_virtual_network.vpc.name
  address_prefixes     = ["10.1.0.0/23"]
}
//10.1.0.0 - 10.1.1.255
resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = var.resource_group.name
  virtual_network_name = azurerm_virtual_network.vpc.name
  address_prefixes     = ["10.1.2.0/27"]
}
//10.1.2.0 - 10.1.2.31
resource "azurerm_subnet" "api-server" {
  name                 = "api-server-${var.env}"
  resource_group_name  = var.resource_group.name
  virtual_network_name = azurerm_virtual_network.vpc.name
  address_prefixes     = ["10.1.3.0/27"]
  delegation {
    name = "aks-delegation"
    service_delegation {
      name    = "Microsoft.ContainerService/managedClusters"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}
//10.1.3.0 - 10.1.3.31
resource "azurerm_subnet" "jumphost_subnet" {
  name                 = "jumphost-subnet-id-${var.env}"
  resource_group_name  = var.resource_group.name
  virtual_network_name = azurerm_virtual_network.vpc.name
  address_prefixes     = ["10.1.3.32/27"]
}
//10.1.3.32 - 10.1.3.63
resource "azurerm_subnet" "data_subnet" {
  name                 = "azure-data-subnet-${var.env}"
  resource_group_name  = var.resource_group.name
  virtual_network_name = azurerm_virtual_network.vpc.name
  address_prefixes     = ["10.1.2.32/27"]
  service_endpoints    = ["Microsoft.Storage"]
  delegation {
    name = "fs"
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }

}
//10.1.2.32 - 10.1.2.63
resource "azurerm_subnet" "redis_subnet" {
  name                 = "redis-subnet-id-${var.env}"
  resource_group_name  = var.resource_group.name
  virtual_network_name = azurerm_virtual_network.vpc.name
  address_prefixes     = ["10.1.2.64/27"]
}
//10.1.2.64
resource "azurerm_network_security_group" "sg" {
  name                = "nsg-${var.env}"
  location            = var.resource_group.location
  resource_group_name = var.resource_group.name
  security_rule {
    access = "Allow"
    direction = "Inbound"
    name = "AllowHTTP"
    priority = 100
    protocol = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    access = "Allow"
    direction = "Inbound"
    name = "AllowHTTPS"
    priority = 101
    protocol = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "sga" {
  subnet_id                 = azurerm_subnet.aks-data-plane.id
  network_security_group_id = azurerm_network_security_group.sg.id
}

# Network contributor role assignments
resource "azurerm_role_assignment" "aks_control_plane" {
  scope                = azurerm_subnet.api-server.id
  role_definition_name = "Network Contributor"
  principal_id         = var.aks_identity_principal_id
}
resource "azurerm_role_assignment" "aks_dataplane" {
  scope                = azurerm_subnet.aks-data-plane.id
  role_definition_name = "Network Contributor"
  principal_id         = var.aks_identity_principal_id
}

