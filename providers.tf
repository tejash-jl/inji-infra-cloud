# terraform {
#   required_version = ">=0.12"

#   required_providers {
#     azapi = {
#       source  = "azure/azapi"
#       version = "~>1.5"
#     }
#     azurerm = {
#       source  = "hashicorp/azurerm"
#       version = "~>2.0"
#     }
#     random = {
#       source  = "hashicorp/random"
#       version = "~>3.0"
#     }
#   }
# }

provider "azurerm" {
  features {}
  
#  skip_provider_registration = true 
  client_id       = "1651961f-e4e4-46b4-9d33-f315061069e9"
  tenant_id       = "6b135b7b-9fb5-41a0-ab57-742f89110b42"
  subscription_id = "aa7bd51f-eda9-4057-a571-6781fb9c557b"
}