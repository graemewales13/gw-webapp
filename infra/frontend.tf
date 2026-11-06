#==============================================================
# Frontend tier: Docker image in ACR, run on Azure Container Apps
#==============================================================

# Basic SKU (~GBP 4/month) doesn't support private endpoints - that needs
# Premium (~GBP 40/month). Access is identity-only: no admin user.
resource "azurerm_container_registry" "this" {
  #checkov:skip=CKV_AZURE_139:Basic SKU has no private endpoints; pull/push is identity-only (no admin user)
  #checkov:skip=CKV_AZURE_163:Vulnerability scanning needs Defender for Containers (paid)
  #checkov:skip=CKV_AZURE_164:Content trust needs Premium SKU
  #checkov:skip=CKV_AZURE_165:Geo-replication needs Premium SKU
  #checkov:skip=CKV_AZURE_166:Quarantine needs Premium SKU
  #checkov:skip=CKV_AZURE_167:Retention policy needs Premium SKU
  #checkov:skip=CKV_AZURE_233:Zone redundancy needs Premium SKU
  #checkov:skip=CKV_AZURE_237:Dedicated data endpoints need Premium SKU
  # Global name, letters and numbers only: cr<org><workload><env><###>
  name                = "crgw${var.app_name}${var.environment}001"
  resource_group_name = azurerm_resource_group.app.name
  location            = azurerm_resource_group.app.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = local.tags
}

resource "azurerm_user_assigned_identity" "frontend" {
  name                = "id-${var.app_name}-frontend-${local.suffix}"
  resource_group_name = azurerm_resource_group.app.name
  location            = azurerm_resource_group.app.location
  tags                = local.tags
}

resource "azurerm_role_assignment" "frontend_acr_pull" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.frontend.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_container_app_environment" "this" {
  name                     = "cae-${var.app_name}-${local.suffix}"
  location                 = azurerm_resource_group.app.location
  resource_group_name      = azurerm_resource_group.app.name
  infrastructure_subnet_id = azapi_resource.subnet["frontend"].id

  # ME_ prefix: Microsoft's convention for Azure-managed resource groups
  infrastructure_resource_group_name = "ME_cae-${var.app_name}-${local.suffix}"

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }

  tags = local.tags
}

resource "azurerm_container_app" "frontend" {
  name                         = "ca-${var.app_name}-frontend-${var.environment}-001"
  container_app_environment_id = azurerm_container_app_environment.this.id
  resource_group_name          = azurerm_resource_group.app.name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"
  tags                         = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.frontend.id]
  }

  registry {
    server   = azurerm_container_registry.this.login_server
    identity = azurerm_user_assigned_identity.frontend.id
  }

  ingress {
    external_enabled = true
    target_port      = var.frontend_port
    transport        = "auto"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 0 # scale to zero when idle: no cost
    max_replicas = 2

    container {
      name   = "frontend"
      image  = var.frontend_bootstrap_image
      cpu    = 0.25
      memory = "0.5Gi"

      # nginx proxies /api/ to the API VM over the VNet
      env {
        name  = "API_UPSTREAM"
        value = "http://${azurerm_network_interface.api.private_ip_address}:${var.api_port}"
      }
    }
  }

  # Terraform creates the app; CI (.github/workflows/frontend.yml)
  # deploys new images. Don't fight it.
  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }

  depends_on = [azurerm_role_assignment.frontend_acr_pull]
}
