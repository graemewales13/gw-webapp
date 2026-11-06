#==============================================================
# API tier: Ubuntu VM configured by Ansible
#
# No public IP and no SSH path in (no Bastion). cloud-init installs
# Ansible and a timer that downloads the config bundle CI published
# (deploy-store.tf) and applies it: every 15 minutes, so drift is
# corrected, and on demand when CI deploys.
#==============================================================

resource "azurerm_user_assigned_identity" "api" {
  name                = "id-${var.app_name}-api-${local.suffix}"
  resource_group_name = azurerm_resource_group.app.name
  location            = azurerm_resource_group.app.location
  tags                = local.tags
}

resource "azurerm_network_interface" "api" {
  name                = "nic-${var.app_name}-api-${local.suffix}"
  location            = azurerm_resource_group.app.location
  resource_group_name = azurerm_resource_group.app.name
  tags                = local.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azapi_resource.subnet["api"].id
    private_ip_address_allocation = "Dynamic"
  }
}

# Azure requires an SSH key on Linux VMs. Nothing can reach port 22, so
# the key is never used; recovery is through the portal's Run Command or
# serial console. The private key stays in (encrypted) Terraform state.
resource "tls_private_key" "api" {
  algorithm = "ED25519"
}

resource "azurerm_linux_virtual_machine" "api" {
  #checkov:skip=CKV_AZURE_50:The VM needs the custom script/cloud-init path to bootstrap Ansible
  #checkov:skip=CKV2_AZURE_12:Backup not needed - the VM is rebuilt from code; data lives in PostgreSQL
  name                  = "vm-${var.app_name}-api-${local.suffix}"
  computer_name         = "${var.app_name}-api-01"
  resource_group_name   = azurerm_resource_group.app.name
  location              = azurerm_resource_group.app.location
  size                  = var.api_vm_size
  admin_username        = "azureadmin"
  network_interface_ids = [azurerm_network_interface.api.id]
  tags                  = local.tags

  disable_password_authentication = true
  admin_ssh_key {
    username   = "azureadmin"
    public_key = tls_private_key.api.public_key_openssh
  }

  # The user-assigned identity is the app's (storage, PostgreSQL). The
  # system-assigned one is for the landing zone's guest configuration
  # policies, which add it if it's missing; declaring it stops Terraform
  # removing it on every run. It's given no roles here.
  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.api.id]
  }

  os_disk {
    name                 = "osdisk-${var.app_name}-api-${local.suffix}"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  # Arm64 image, to match the Arm64 B2pts_v2 size.
  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server-arm64"
    version   = "latest"
  }

  # Free: Azure Update Manager reports missing patches. Ansible turns on
  # unattended-upgrades to install security updates.
  patch_assessment_mode = "AutomaticByPlatform"

  boot_diagnostics {} # managed storage account, free

  custom_data = base64encode(templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
    bundle_url = "${azurerm_storage_account.deploy.primary_blob_endpoint}${azurerm_storage_container.deploy.name}/api-bundle.tar.gz"
    client_id  = azurerm_user_assigned_identity.api.client_id
    app_vars = yamlencode({
      api_port        = var.api_port
      db_host         = azurerm_postgresql_flexible_server.this.fqdn
      db_name         = azurerm_postgresql_flexible_server_database.app.name
      db_user         = azurerm_user_assigned_identity.api.name
      azure_client_id = azurerm_user_assigned_identity.api.client_id
    })
  }))

  depends_on = [azurerm_role_assignment.api_bundle_read]
}
