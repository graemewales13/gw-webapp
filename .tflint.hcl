# tflint configuration - used locally and by .github/workflows/ci.yml
# Run from the repo root:  tflint --init && tflint --chdir=infra --config "$(pwd)/.tflint.hcl"

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "azurerm" {
  enabled = true
  version = "0.32.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

# Test app: it's meant to be destroyed when not in use to save money.
# A production database would set prevent_destroy.
rule "azurerm_resources_missing_prevent_destroy" {
  enabled = false
}
