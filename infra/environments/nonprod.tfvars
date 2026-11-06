# subscription_id comes from the nonprod GitHub environment (AZURE_SUBSCRIPTION_ID).

app_name    = "webapp"
environment = "nonprod"
location    = "eastasia"

tags = {
  app             = "webapp"
  env             = "nonprod"
  region          = "eastasia"
  criticality     = "low"
  confidentiality = "private"
  businessunit    = "apps"
  opsteam         = "app-team"
  repo            = "https://github.com/gw-avm/gw-webapp"
  deployed_by     = "terraform"
}

# Created by vending (landing-zones/nonprod.tfvars)
spoke_vnet = {
  name                = "vnet-apps-nonprod-eastasia-001"
  resource_group_name = "rg-apps-network-nonprod-eastasia-001"
}

# Platform-owned, in the connectivity subscription
postgres_private_dns_zone_id = "/subscriptions/ce882887-4b87-4377-bc63-076ec3c22a85/resourceGroups/rg-connectivity-dns-prod-eastasia-001/providers/Microsoft.Network/privateDnsZones/privatelink.postgres.database.azure.com"

# Inside the spoke's 10.0.4.0/22
subnet_prefixes = {
  frontend          = "10.0.4.0/27"
  api               = "10.0.4.32/27"
  private_endpoints = "10.0.4.64/28"
}

github_repository = {
  owner    = "gw-avm"
  owner_id = 351889910
  name     = "gw-webapp"
  repo_id  = 1437058694
}
