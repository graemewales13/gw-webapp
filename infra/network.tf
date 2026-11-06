#==============================================================
# Subnets in the vended spoke VNet, one per tier, each with its own NSG.
# Traffic flow allowed:
#   Internet -> frontend :80/443 -> api :api_port -> postgres :5432
#
# The landing zone's Deny-Subnet-Without-Nsg policy refuses a subnet that
# is created first and given its NSG afterwards, so each subnet is created
# with its NSG in one request (azapi rather than azurerm_subnet).
#==============================================================

#--------------------------------------------------------------
# Frontend: Container Apps environment (workload profiles)
#--------------------------------------------------------------
resource "azurerm_network_security_group" "frontend" {
  name                = "nsg-${var.app_name}-frontend-${local.suffix}"
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

#--------------------------------------------------------------
# API: Linux VMs, reachable only from the frontend subnet
#--------------------------------------------------------------
resource "azurerm_network_security_group" "api" {
  name                = "nsg-${var.app_name}-api-${local.suffix}"
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

#--------------------------------------------------------------
# Private endpoints: PostgreSQL, reachable only from the API subnet
#--------------------------------------------------------------
resource "azurerm_network_security_group" "private_endpoints" {
  name                = "nsg-${var.app_name}-pe-${local.suffix}"
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

#--------------------------------------------------------------
# Subnets
#--------------------------------------------------------------
locals {
  subnets = {
    frontend = {
      address_prefix = var.subnet_prefixes.frontend
      nsg_id         = azurerm_network_security_group.frontend.id
      delegation     = "Microsoft.App/environments"
      # Container Apps and the VM need outbound internet (images, apt, pip).
      # Default outbound access is free but being retired by Azure;
      # production would use a NAT Gateway or the hub firewall.
      default_outbound_access = true
    }
    api = {
      address_prefix          = var.subnet_prefixes.api
      nsg_id                  = azurerm_network_security_group.api.id
      delegation              = null
      default_outbound_access = true
    }
    pe = {
      address_prefix          = var.subnet_prefixes.private_endpoints
      nsg_id                  = azurerm_network_security_group.private_endpoints.id
      delegation              = null
      default_outbound_access = false
    }
  }
}

resource "azapi_resource" "subnet" {
  for_each  = local.subnets
  type      = "Microsoft.Network/virtualNetworks/subnets@2024-07-01"
  name      = "snet-${var.app_name}-${each.key}-${local.suffix}"
  parent_id = data.azurerm_virtual_network.spoke.id

  body = {
    properties = merge(
      {
        addressPrefix         = each.value.address_prefix
        defaultOutboundAccess = each.value.default_outbound_access
        networkSecurityGroup = {
          id = each.value.nsg_id
        }
        # Lets the NSG apply to private endpoints in this subnet.
        privateEndpointNetworkPolicies = "Enabled"
      },
      each.value.delegation == null ? {} : {
        delegations = [{
          name = "delegation"
          properties = {
            serviceName = each.value.delegation
          }
        }]
      }
    )
  }

  # Azure allows one subnet change on a VNet at a time.
  locks = [data.azurerm_virtual_network.spoke.id]

  # After a destroy removes the Container Apps environment, Azure takes a
  # few minutes to release its hold on the frontend subnet.
  retry = {
    error_message_regex = ["InUseSubnetCannotBeDeleted", "AnotherOperationInProgress"]
  }

  response_export_values = []
}
