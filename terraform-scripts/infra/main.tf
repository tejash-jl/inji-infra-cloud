resource "azurerm_resource_group" "rg" {
  name     = "inji-rg-${var.env}"
  location = var.region
}

module "identities" {
  source         = "./modules/identity"
  resource_group = azurerm_resource_group.rg
  env = var.env
}

module "network" {
  source                    = "./modules/network"
  resource_group            = azurerm_resource_group.rg
  aks_identity_principal_id = module.identities.aks_identity_principal_id
  env = var.env
}

module "aks" {
  source                 = "./modules/aks"
  resource_group         = azurerm_resource_group.rg
  subnet_id              = module.network.aks_dataplane_subnet_id
  api_server_subnet_id   = module.network.api_server_subnet_id
  api_server_identity_id = module.identities.aks_identity_id
  #  api_server_allowed_cidr_blocks = module.network.jumphost_subnet_cidr_blocks
  env = var.env
  depends_on = [module.bastion]
}

module "bastion" {
  source             = "./modules/bastion"
  resource_group     = azurerm_resource_group.rg
  subnet_id          = module.network.bastion_subnet_id
  subnet_jumphost_id = module.network.jumphost_subnet_id
  admin_password     = var.bastion_admin_password
  ssh_public_key     = var.ssh_public_key
  env = var.env
  vnet_id = module.network.vpc_id
}

module "psql" {
  source = "./modules/psql"
  resource_group     = azurerm_resource_group.rg
  subnet_id = module.network.data_subnet_id
  vpc_id = module.network.vpc_id
  env = var.env
  depends_on = [module.bastion]
}

//resource "azurerm_virtual_network" "vpc" {
//  name                = "esignet-${var.env}-vpc"
//  location            = azurerm_resource_group.rg.location
//  resource_group_name = azurerm_resource_group.rg.name
//  address_space       = ["10.0.0.0/8"]
//}
//
//resource "azurerm_subnet" "new_esignet_subnet" {
//  name                 = "aks_subnet"
//  resource_group_name  = azurerm_resource_group.rg.name
//  virtual_network_name = azurerm_virtual_network.vpc.name
//  address_prefixes     = ["10.240.0.0/16"]
//}
//
//resource "random_pet" "azurerm_kubernetes_cluster_dns_prefix" {
//  prefix = "dns"
//}
//
//resource "azurerm_kubernetes_cluster" "k8s" {
//  location            = azurerm_resource_group.rg.location
//  name                = "inji-${var.env}-aks"
//  resource_group_name = azurerm_resource_group.rg.name
//  dns_prefix          = random_pet.azurerm_kubernetes_cluster_dns_prefix.id
//
//  identity {
//    type = "SystemAssigned"
//  }
//
//  default_node_pool {
//    name       = "agentpool"
//    vm_size    = "Standard_B2pls_v2"
//    node_count = var.node_count
//    vnet_subnet_id = azurerm_subnet.new_esignet_subnet.id
//  }
//  linux_profile {
//    admin_username = var.username
//
//    ssh_key {
//      key_data = azapi_resource_action.ssh_public_key_gen.output.publicKey
//    }
//  }
//  network_profile {
//    network_plugin    = "kubenet"
//    load_balancer_sku = "standard"
//  }
//}
//
//resource "random_pet" "ssh_key_name" {
//  prefix    = "ssh"
//  separator = ""
//}
//
//resource "azapi_resource_action" "ssh_public_key_gen" {
//  type        = "Microsoft.Compute/sshPublicKeys@2022-11-01"
//  resource_id = azapi_resource.ssh_public_key.id
//  action      = "generateKeyPair"
//  method      = "POST"
//
//  response_export_values = ["publicKey", "privateKey"]
//}
//
//resource "azapi_resource" "ssh_public_key" {
//  type      = "Microsoft.Compute/sshPublicKeys@2022-11-01"
//  name      = random_pet.ssh_key_name.id
//  location  = azurerm_resource_group.rg.location
//  parent_id = azurerm_resource_group.rg.id
//}
