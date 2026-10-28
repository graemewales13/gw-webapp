locals {
  # gw-<app>-<env>, e.g. gw-webapp-prod
  name           = "gw-${var.app_name}-${var.environment}"
  location_short = { uksouth = "uks", ukwest = "ukw" }[var.location]

  # The landing zone's Modify policy copies RG tags onto resources, so
  # every resource gets the same tags to avoid a permanent diff.
  tags = var.tags
}

data "azurerm_client_config" "current" {}

data "azurerm_virtual_network" "spoke" {
  name                = var.spoke_vnet.name
  resource_group_name = var.spoke_vnet.resource_group_name
}

resource "azurerm_resource_group" "app" {
  name     = "rg-${local.name}-${local.location_short}"
  location = var.location
  tags     = local.tags
}
