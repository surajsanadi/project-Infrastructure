# ─────────────────────────────────────────
# TERRAFORM & PROVIDER CONFIGURATION
# ─────────────────────────────────────────
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
  required_version = ">= 1.6.6"
  backend "local" {}        # ← only line added
}

provider "azurerm" {
  features {}
}
