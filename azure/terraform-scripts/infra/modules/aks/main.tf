resource "random_pet" "azurerm_kubernetes_cluster_dns_prefix" {
  prefix = "dns"
}

resource "azurerm_kubernetes_cluster" "cluster" {
  name                = "inji-aks-${var.env}"
  location            = var.resource_group.location
  resource_group_name = var.resource_group.name
  dns_prefix          = random_pet.azurerm_kubernetes_cluster_dns_prefix.id

  default_node_pool {
    name           = "default"
    node_count     = 3
    vm_size        = "Standard_B4als_v2"
    vnet_subnet_id = var.subnet_id
    temporary_name_for_rotation = "old"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [var.api_server_identity_id]
  }

  lifecycle {
    ignore_changes = [
      azure_policy_enabled,
      microsoft_defender
    ]
  }

  role_based_access_control_enabled = true
  private_cluster_enabled           = true

  network_profile {
    network_plugin    = "azure"
    network_policy    = "calico"
    dns_service_ip    = "10.0.0.10"
    service_cidr      = "10.0.0.0/16"
    load_balancer_sku = "standard"
  }



//  api_server_access_profile {
//    #    authorized_ip_ranges     = var.api_server_allowed_cidr_blocks
//  }

  tags = {
    Environment = var.env
  }


  node_resource_group = "inji_node_rg_${var.env}"
}

# Bastion
resource "azurerm_public_ip" "lb_ip" {
  name                = "glb-ip-${var.env}"
  location            = var.resource_group.location
  resource_group_name = azurerm_kubernetes_cluster.cluster.node_resource_group
  allocation_method   = "Static"
  sku                 = "Standard"
  depends_on = [azurerm_kubernetes_cluster.cluster]
}