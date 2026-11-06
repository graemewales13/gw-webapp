#==============================================================
# Identity for the frontend and api deploy workflows. OIDC federation, no
# secrets. The workflows run in this environment's GitHub environment
# (which only allows main), so that's what the identity trusts.
#   frontend.yml: push images to ACR, roll the container app
#   api.yml:      upload the config bundle, tell the VM to apply it
#
# The landing zone's deploy identity may only grant these roles, so each
# is the narrowest that does the job.
#==============================================================

resource "azurerm_user_assigned_identity" "github" {
  name                = "id-${var.app_name}-github-${local.suffix}"
  resource_group_name = azurerm_resource_group.app.name
  location            = azurerm_resource_group.app.location
  tags                = local.tags
}

# GitHub's immutable subject: owner and repo IDs as well as names. A job in
# an environment presents the environment, not the branch.
resource "azurerm_federated_identity_credential" "github" {
  name      = "github-${var.environment}"
  parent_id = azurerm_user_assigned_identity.github.id
  audience  = ["api://AzureADTokenExchange"]
  issuer    = "https://token.actions.githubusercontent.com"
  subject   = "repo:${var.github_repository.owner}@${var.github_repository.owner_id}/${var.github_repository.name}@${var.github_repository.repo_id}:environment:${var.environment}"
}

resource "azurerm_role_assignment" "github" {
  for_each = {
    acr_push = { scope = azurerm_container_registry.this.id, role = "AcrPush" }
    app      = { scope = azurerm_container_app.frontend.id, role = "Container Apps Contributor" }
    env_read = { scope = azurerm_container_app_environment.this.id, role = "Reader" }
    bundle   = { scope = azurerm_storage_container.deploy.id, role = "Storage Blob Data Contributor" }
    api_vm   = { scope = azurerm_linux_virtual_machine.api.id, role = "Virtual Machine Contributor" } # Run Command
  }

  scope                = each.value.scope
  role_definition_name = each.value.role
  principal_id         = azurerm_user_assigned_identity.github.principal_id
  principal_type       = "ServicePrincipal"
}
