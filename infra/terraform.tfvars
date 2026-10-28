# subscription_id is a workspace variable written by the landing zone bootstrap.

app_name    = "webapp"
environment = "prod"
location    = "uksouth"

tags = {
  environment = "prod"
  owner       = "app-team"
  workload    = "gw-webapp"
}

# Created by the landing zone platform (module.spoke_prod)
spoke_vnet = {
  name                = "vnet-gw-prod-uks"
  resource_group_name = "rg-gw-prod-network-uks"
}

# Inside the spoke's 10.1.0.0/16
subnet_prefixes = {
  frontend          = "10.1.0.0/27"
  api               = "10.1.1.0/24"
  private_endpoints = "10.1.2.0/24"
}

github_repo = "graemewales13/gw-webapp"
