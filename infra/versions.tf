terraform {
  required_version = ">= 1.6.0"

  # Workspace, deployment identities and subscription_id are vended by
  # the landing zone bootstrap (workload_workspaces).
  cloud {
    organization = "graemewales_org"

    workspaces {
      project = "apps"
      name    = "gw-webapp-prod"
    }
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.9"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id

  # Register only what this app uses, not the provider's long default list
  resource_provider_registrations = "core"
  resource_providers_to_register = [
    "Microsoft.App",
    "Microsoft.ContainerRegistry",
    "Microsoft.DBforPostgreSQL",
    "Microsoft.OperationalInsights",
  ]
}
