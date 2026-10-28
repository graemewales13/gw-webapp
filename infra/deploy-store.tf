#==============================================================
# Deploy store: the API's config bundle (ansible/ + api/)
# CI uploads it (Storage Blob Data Contributor); the API VM downloads
# it (Storage Blob Data Reader). Both use Entra ID, never keys or SAS.
# Blob versioning keeps every bundle, so a rollback is a restore.
#==============================================================

resource "azurerm_storage_account" "deploy" {
  #checkov:skip=CKV_AZURE_59:GitHub-hosted runners upload from the internet; access is Entra ID only
  #checkov:skip=CKV2_AZURE_33:No private endpoint - runners can't reach one; saves ~GBP 6/month
  #checkov:skip=CKV2_AZURE_40:Shared keys stay enabled because azurerm refreshes data-plane settings with them; nobody is given keys and OAuth is the default
  #checkov:skip=CKV2_AZURE_41:No SAS tokens are issued
  #checkov:skip=CKV2_AZURE_1:Customer-managed keys need Key Vault; Microsoft-managed encryption is fine for config bundles
  #checkov:skip=CKV_AZURE_206:LRS is enough - bundles can be rebuilt by CI
  #checkov:skip=CKV_AZURE_33:No queues are used
  name                            = substr(replace("st${local.name}${local.location_short}", "-", ""), 0, 24)
  resource_group_name             = azurerm_resource_group.app.name
  location                        = azurerm_resource_group.app.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  default_to_oauth_authentication = true
  tags                            = local.tags

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }
}

resource "azurerm_storage_container" "deploy" {
  #checkov:skip=CKV2_AZURE_21:Blob logs go to the central Log Analytics workspace through the landing zone's diagnostic settings policy
  name                 = "deploy"
  storage_account_id    = azurerm_storage_account.deploy.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "api_bundle_read" {
  scope                = azurerm_storage_container.deploy.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.api.principal_id
  principal_type       = "ServicePrincipal"
}
