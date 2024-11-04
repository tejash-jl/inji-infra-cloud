terraform {
  backend "azurerm" {
    resource_group_name  = "tfstate-rg-dev"
    storage_account_name = "injistatedev"
    container_name       = "tfstatedev"
    key                  = "terraform.tfstate"
  }
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=4.1.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = "2.0.0-beta"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.6.3"
    }
    time = {
      source  = "hashicorp/time"
      version = "0.12.1"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }

}
  subscription_id = var.subscription_id
}