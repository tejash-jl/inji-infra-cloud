data "azurerm_virtual_machine" "current" {
  name = "bastion-vm-${var.env}"
  resource_group_name = var.resource_group.name
}

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "kv" {
  name                       = "psql-kv-${var.env}"
  location                   = var.resource_group.location
  resource_group_name        = var.resource_group.name
  tenant_id                  = data.azurerm_virtual_machine.current.identity.0.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled = false
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Create",
      "Get",
    ]

    secret_permissions = [
      "Set",
      "Get",
      "Delete",
      "Purge",
      "Recover"
    ]
  }
  access_policy {
    tenant_id = data.azurerm_virtual_machine.current.identity.0.tenant_id
    object_id = data.azurerm_virtual_machine.current.identity.0.principal_id

    key_permissions = [
      "Create",
      "Get",
    ]

    secret_permissions = [
      "Set",
      "Get",
      "Delete",
      "Purge",
      "Recover"
    ]
  }
}

resource "azurerm_key_vault_secret" "kvs" {
  name         = "psql-password"
  value        = random_password.password.result
  key_vault_id = azurerm_key_vault.kv.id
}

resource "random_password" "password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "azurerm_postgresql_flexible_server" "psql" {
  name                          = "inji-psql-${var.env}"
  resource_group_name           = var.resource_group.name
  location                      = var.resource_group.location
  version                       = "16"
  delegated_subnet_id           = var.subnet_id
  public_network_access_enabled = false
  administrator_login           = "psqladmin"
  administrator_password        = random_password.password.result
  zone                          = "1"

  storage_mb   = 32768
  storage_tier = "P4"

  sku_name   = "B_Standard_B1ms"
  private_dns_zone_id           = azurerm_private_dns_zone.example.id

}

resource "azurerm_private_dns_zone" "example" {
  name                = "inji.postgres.database.azure.com"
  resource_group_name = var.resource_group.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "example" {
  name                  = "injipsql.com"
  private_dns_zone_name = azurerm_private_dns_zone.example.name
  virtual_network_id    = var.vpc_id
  resource_group_name   = var.resource_group.name
}

resource "azurerm_postgresql_flexible_server_database" "db" {
  count      = length(var.db_info)
  name       = var.db_info[count.index]

  server_id = azurerm_postgresql_flexible_server.psql.id
  collation = "en_US.utf8"
  charset   = "utf8"

  # prevent the possibility of accidental data loss

}

resource "azurerm_postgresql_flexible_server_configuration" "max_connections" {
  server_id = azurerm_postgresql_flexible_server.psql.id
  name      = "max_connections"
  value     = 100
}