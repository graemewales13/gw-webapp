terraform {
  required_version = ">= 1.6.0"

  # State lives in the landing zone's own storage account, which vending
  # creates. The workflow supplies the settings (one state file per
  # environment) and signs in with Entra ID: no storage keys.
  backend "azurerm" {}

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.10"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id

  # The providers this app uses are already registered in the landing zone,
  # and the read-only plan identity couldn't register them anyway.
  resource_provider_registrations = "none"

  # Storage settings are read through Azure Resource Manager, so Terraform
  # never needs storage account keys.
  storage_use_azuread = true
  features {
    storage {
      data_plane_available = false
    }
  }
}

provider "azapi" {
  subscription_id = var.subscription_id
}
