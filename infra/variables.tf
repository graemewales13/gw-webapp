#--------------------------------------------------------------
# Set by the landing zone bootstrap - don't add to tfvars
#--------------------------------------------------------------
variable "subscription_id" {
  description = "Landing zone subscription (gw-apps-prod). Workspace variable written by the bootstrap."
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
}

variable "location" {
  type    = string
  default = "uksouth"
}

variable "tags" {
  description = "Must include the tags the landing zone requires on resource groups (environment, owner)."
  type        = map(string)
}

#--------------------------------------------------------------
# Landing zone network (owned by the platform; subnets are ours)
#--------------------------------------------------------------
variable "spoke_vnet" {
  description = "The spoke VNet the platform created for this landing zone."
  type = object({
    name                = string
    resource_group_name = string
  })
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
    B2pts v2: 2 vCPU (Arm64), 1 GiB, ~GBP 6/month in East Asia. Arm64 sizes
    need the Arm64 image (see api.tf); the subscription has Bpsv2 quota there.
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
variable "github_repo" {
  description = "owner/repo of this repository."
  type        = string
}

variable "github_branch" {
  description = "Branch CI deploys from. Only workflows on it can sign in to Azure."
  type        = string
  default     = "main"
}
