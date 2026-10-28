#==============================================================
# Subnets in the platform-owned spoke VNet, one per tier, each with
# its own NSG. Traffic flow allowed:
#   Internet -> frontend :80/443 -> api :api_port -> postgres :5432
#==============================================================

#--------------------------------------------------------------
# Frontend: Container Apps environment (workload profiles)
#--------------------------------------------------------------
resource "azurerm_subnet" "frontend" {
  name                 = "snet-${var.app_name}-frontend"
  resource_group_name  = data.azurerm_virtual_network.spoke.resource_group_name
  virtual_network_name = data.azurerm_virtual_network.spoke.name
  address_prefixes     = [var.subnet_prefixes.frontend]

  delegation {
    name = "container-apps"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_network_security_group" "frontend" {
  name                = "nsg-${local.name}-frontend-${local.location_short}"
  location            = azurerm_resource_group.app.location
  resource_group_name = azurerm_resource_group.app.name
  tags                = local.tags

  #checkov:skip=CKV_AZURE_160:Public web frontend - HTTP is redirected to HTTPS by Container Apps ingress
  security_rule {
    name                       = "allow-web-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "Internet"
    source_port_range          = "*"
    destination_address_prefix = var.subnet_prefixes.frontend
    destination_port_ranges    = ["80", "443"]
  }
}

resource "azurerm_subnet_network_security_group_association" "frontend" {
  subnet_id                 = azurerm_subnet.frontend.id
  network_security_group_id = azurerm_network_security_group.frontend.id
}

#--------------------------------------------------------------
# API: Linux VMs, reachable only from the frontend subnet
#--------------------------------------------------------------
resource "azurerm_subnet" "api" {
  name                 = "snet-${var.app_name}-api"
  resource_group_name  = data.azurerm_virtual_network.spoke.resource_group_name
  virtual_network_name = data.azurerm_virtual_network.spoke.name
  address_prefixes     = [var.subnet_prefixes.api]

  # The VM has no public IP. It needs outbound internet for apt, pip and
  # ansible-pull from GitHub. Default outbound access is free but being
  # retired; production would use a NAT Gateway (~GBP 25/month) or the
  # hub firewall.
  default_outbound_access_enabled = true
}

resource "azurerm_network_security_group" "api" {
  name                = "nsg-${local.name}-api-${local.location_short}"
  location            = azurerm_resource_group.app.location
  resource_group_name = azurerm_resource_group.app.name
  tags                = local.tags

  security_rule {
    name                       = "allow-frontend-to-api"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = var.subnet_prefixes.frontend
    source_port_range          = "*"
    destination_address_prefix = var.subnet_prefixes.api
    destination_port_range     = tostring(var.api_port)
  }

  # The default rules allow anything from the VNet, which includes the
  # hub and (through it) other spokes. Close that off.
  security_rule {
    name                       = "deny-vnet-inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_address_prefix      = "VirtualNetwork"
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "api" {
  subnet_id                 = azurerm_subnet.api.id
  network_security_group_id = azurerm_network_security_group.api.id
}

#--------------------------------------------------------------
# Private endpoints: PostgreSQL, reachable only from the API subnet
#--------------------------------------------------------------
resource "azurerm_subnet" "private_endpoints" {
  name                              = "snet-${var.app_name}-pe"
  resource_group_name               = data.azurerm_virtual_network.spoke.resource_group_name
  virtual_network_name              = data.azurerm_virtual_network.spoke.name
  address_prefixes                  = [var.subnet_prefixes.private_endpoints]
  private_endpoint_network_policies = "Enabled" # lets the NSG apply to private endpoints
  default_outbound_access_enabled   = false
}

resource "azurerm_network_security_group" "private_endpoints" {
  name                = "nsg-${local.name}-pe-${local.location_short}"
  location            = azurerm_resource_group.app.location
  resource_group_name = azurerm_resource_group.app.name
  tags                = local.tags

  security_rule {
    name                       = "allow-api-to-postgres"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = var.subnet_prefixes.api
    source_port_range          = "*"
    destination_address_prefix = var.subnet_prefixes.private_endpoints
    destination_port_range     = "5432"
  }

  security_rule {
    name                       = "deny-vnet-inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_address_prefix      = "VirtualNetwork"
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "private_endpoints" {
  subnet_id                 = azurerm_subnet.private_endpoints.id
  network_security_group_id = azurerm_network_security_group.private_endpoints.id
}
