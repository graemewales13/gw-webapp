#==============================================================
# Database tier: PostgreSQL Flexible Server
# - Private endpoint only, no public network access
# - Entra ID authentication only, no passwords anywhere
#==============================================================

resource "azurerm_postgresql_flexible_server" "this" {
  #checkov:skip=CKV_AZURE_136:Geo-redundant backups not available on Burstable SKU and not needed for a test app
  name                          = "psql-${local.name}-${local.location_short}"
  resource_group_name           = azurerm_resource_group.app.name
  location                      = azurerm_resource_group.app.location
  version                       = var.postgres_version
  sku_name                      = var.postgres_sku
  storage_mb                    = 32768
  backup_retention_days         = 7
  public_network_access_enabled = false
  tags                          = local.tags

  authentication {
    active_directory_auth_enabled = true
    password_auth_enabled         = false
    tenant_id                     = data.azurerm_client_config.current.tenant_id
  }

  # Azure picks a zone at creation; don't try to move it afterwards
  lifecycle {
    ignore_changes = [zone]
  }
}

resource "azurerm_postgresql_flexible_server_database" "app" {
  name      = var.app_name
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# The API VM's managed identity is the Entra admin, so the app connects
# with a token, not a password. Fine for a test app; in production the
# admin would be a DBA group and the app would get its own limited role.
resource "azurerm_postgresql_flexible_server_active_directory_administrator" "api" {
  server_name         = azurerm_postgresql_flexible_server.this.name
  resource_group_name = azurerm_resource_group.app.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  object_id           = azurerm_user_assigned_identity.api.principal_id
  principal_name      = azurerm_user_assigned_identity.api.name
  principal_type      = "ServicePrincipal"
}

resource "azurerm_private_endpoint" "postgres" {
  name                          = "pe-${local.name}-psql-${local.location_short}"
  location                      = azurerm_resource_group.app.location
  resource_group_name           = azurerm_resource_group.app.name
  subnet_id                     = azurerm_subnet.private_endpoints.id
  custom_network_interface_name = "nic-pe-${local.name}-psql-${local.location_short}"
  tags                          = local.tags

  private_service_connection {
    name                           = "psql"
    private_connection_resource_id = azurerm_postgresql_flexible_server.this.id
    subresource_names              = ["postgresqlServer"]
    is_manual_connection           = false
  }

  # The landing zone's DNS policy adds the zone group (and the A record
  # in the central privatelink zone) a few minutes after creation.
  lifecycle {
    ignore_changes = [private_dns_zone_group]
  }
}
