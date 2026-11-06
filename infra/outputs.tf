# Used by the destroy run to find policy-created resources to remove first.
output "resource_group_name" {
  value = azurerm_resource_group.app.name
}

output "frontend_url" {
  value = "https://${azurerm_container_app.frontend.ingress[0].fqdn}"
}

output "api_private_ip" {
  value = azurerm_network_interface.api.private_ip_address
}

output "postgres_fqdn" {
  value = azurerm_postgresql_flexible_server.this.fqdn
}

# Set these as GitHub repository variables (Settings -> Secrets and
# variables -> Actions -> Variables) for .github/workflows/frontend.yml
output "github_actions_variables" {
  value = {
    AZURE_CLIENT_ID       = azurerm_user_assigned_identity.github.client_id
    AZURE_TENANT_ID       = data.azurerm_client_config.current.tenant_id
    AZURE_SUBSCRIPTION_ID = var.subscription_id
    ACR_NAME              = azurerm_container_registry.this.name
    CONTAINER_APP_NAME    = azurerm_container_app.frontend.name
    RESOURCE_GROUP        = azurerm_resource_group.app.name
    STORAGE_ACCOUNT       = azurerm_storage_account.deploy.name
    API_VM_NAME           = azurerm_linux_virtual_machine.api.name
  }
}
