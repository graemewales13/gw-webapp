#==============================================================
# Database tier: PostgreSQL Flexible Server
# - Private endpoint only, no public network access
# - Entra ID authentication only, no passwords anywhere
#==============================================================

resource "azurerm_postgresql_flexible_server" "this" {
  #checkov:skip=CKV_AZURE_136:Geo-redundant backups not available on Burstable SKU and not needed for a test app
  name                          = "psql-${var.app_name}-${local.suffix}"
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
  name                          = "pe-${var.app_name}-psql-${local.suffix}"
  location                      = azurerm_resource_group.app.location
  resource_group_name           = azurerm_resource_group.app.name
  subnet_id                     = azapi_resource.subnet["pe"].id
  custom_network_interface_name = "nic-pe-${var.app_name}-psql-${local.suffix}"
  tags                          = local.tags

  private_service_connection {
    name                           = "psql"
    private_connection_resource_id = azurerm_postgresql_flexible_server.this.id
    subresource_names              = ["postgresqlServer"]
    is_manual_connection           = false
  }

  # Not yet registered in the platform's central
  # privatelink.postgres.database.azure.com zone: that DNS zone group is a
  # follow-up change. Until then the API can't resolve the database.
  lifecycle {
    ignore_changes = [private_dns_zone_group]
  }
}
