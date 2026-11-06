#--------------------------------------------------------------
# Set by the workflow from the GitHub environment - don't add to tfvars
#--------------------------------------------------------------
variable "subscription_id" {
  description = "The landing zone subscription (AZURE_SUBSCRIPTION_ID in the GitHub environment)."
  type        = string
}

#--------------------------------------------------------------
# App
#--------------------------------------------------------------
variable "app_name" {
  description = "Short app name used in resource names."
  type        = string
  default     = "webapp"

  validation {
    condition     = can(regex("^[a-z0-9]{2,12}$", var.app_name))
    error_message = "app_name must be 2-12 lowercase letters or numbers."
  }
}

variable "environment" {
  type = string

  validation {
    condition     = contains(["nonprod", "prod"], var.environment)
    error_message = "environment must be nonprod or prod."
  }
}

variable "location" {
  type    = string
  default = "eastasia"
}

variable "tags" {
  description = "CAF tags applied to every resource."
  type        = map(string)
}

#--------------------------------------------------------------
# Landing zone network (owned by vending; subnets are ours)
#--------------------------------------------------------------
variable "spoke_vnet" {
  description = "The spoke VNet vending created for this landing zone."
  type = object({
    name                = string
    resource_group_name = string
  })
}

variable "postgres_private_dns_zone_id" {
  description = "The platform's central privatelink.postgres.database.azure.com zone. A plain ID, so plans never need to read the connectivity subscription."
  type        = string
}

variable "subnet_prefixes" {
  description = "Address ranges inside the spoke for this app's subnets."
  type = object({
    frontend          = string # Container Apps environment, /27 minimum
    api               = string # API VMs
    private_endpoints = string
  })
}

#--------------------------------------------------------------
# Tiers
#--------------------------------------------------------------
variable "frontend_bootstrap_image" {
  description = "Image the container app starts with (must listen on frontend_port). CI deploys the real image; Terraform ignores image changes afterwards."
  type        = string
  default     = "docker.io/nginxinc/nginx-unprivileged:1.28-alpine"
}

variable "frontend_port" {
  type    = number
  default = 8080
}

variable "api_vm_size" {
  description = <<-EOT
    B2pts_v2: 2 vCPU (Arm64), 1 GiB, in the landing zone's Bpsv2 quota.
    This size doesn't support Trusted Launch, so the VM uses standard
    security (the ALZ Trusted Launch policy only audits).
  EOT
  type        = string
  default     = "Standard_B2pts_v2"
}

variable "api_port" {
  type    = number
  default = 8000
}

variable "postgres_sku" {
  type    = string
  default = "B_Standard_B1ms"
}

variable "postgres_version" {
  type    = string
  default = "16"
}

#--------------------------------------------------------------
# GitHub Actions OIDC
#--------------------------------------------------------------
variable "github_repository" {
  description = "This repository. GitHub's OIDC subject includes the owner and repo IDs: gh api repos/<owner>/<name> (.owner.id, .id)."
  type = object({
    owner    = string
    owner_id = number
    name     = string
    repo_id  = number
  })
}
