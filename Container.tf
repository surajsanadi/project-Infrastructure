terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.9"
    }
  }
  required_version = ">= 1.5.0"
}

provider "azurerm" {
  features {}
}

# ── Resource Group ──────────────────────────────────────────

resource "azurerm_resource_group" "rg" {
  name     = "medical-chatbot-rg"
  location = "eastus"
}

# ── Log Analytics Workspace ─────────────────────────────────

resource "azurerm_log_analytics_workspace" "law" {
  name                = "medical-chatbot-law"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# ── Container Apps Environment ──────────────────────────────

resource "azurerm_container_app_environment" "env" {
  name                       = "medical-chatbot-env"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
}

# ── Azure Container Registry ────────────────────────────────

resource "azurerm_container_registry" "acr" {
  name                = "medchatbotacrv2prod"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = true
}

# ── Storage Account + Blob Container ───────────────────────

resource "azurerm_storage_account" "storage" {
  name                     = "medchatbotstorev2"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
}

resource "azurerm_storage_container" "endpoints" {
  name                  = "endpoints"
  storage_account_name  = azurerm_storage_account.storage.name
  container_access_type = "private"
}

# ── Blue Container App ──────────────────────────────────────
# Using public placeholder image until you push your own image to ACR.
# Once you push your image, replace the image value with:
# "${azurerm_container_registry.acr.login_server}/medical-chatbot:latest"
# and add back the registry + acr-password secret blocks.

resource "azurerm_container_app" "blue" {
  name                         = "medical-chatbot-blue"
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"

  secret {
    name  = "storage-conn"
    value = azurerm_storage_account.storage.primary_connection_string
  }

  template {
    container {
      name   = "blue-app"
      image  = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "APP_ENV"
        value = "blue"
      }
      env {
        name        = "AZURE_STORAGE_CONNECTION_STRING"
        secret_name = "storage-conn"
      }
      env {
        name  = "BLOB_CONTAINER_NAME"
        value = "endpoints"
      }
    }
    min_replicas = 1
    max_replicas = 3
  }

  ingress {
    external_enabled = true
    target_port      = 8000
    transport        = "http"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  depends_on = [
    azurerm_container_app_environment.env,
    azurerm_storage_account.storage
  ]
}

# ── Green Container App ─────────────────────────────────────

resource "azurerm_container_app" "green" {
  name                         = "medical-chatbot-green"
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"

  secret {
    name  = "storage-conn"
    value = azurerm_storage_account.storage.primary_connection_string
  }

  template {
    container {
      name   = "green-app"
      image  = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "APP_ENV"
        value = "green"
      }
      env {
        name        = "AZURE_STORAGE_CONNECTION_STRING"
        secret_name = "storage-conn"
      }
      env {
        name  = "BLOB_CONTAINER_NAME"
        value = "endpoints"
      }
    }
    min_replicas = 1
    max_replicas = 3
  }

  ingress {
    external_enabled = true
    target_port      = 8000
    transport        = "http"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  depends_on = [
    azurerm_container_app_environment.env,
    azurerm_storage_account.storage
  ]
}

# ── Outputs ─────────────────────────────────────────────────

output "acr_login_server" {
  description = "Push your Docker image to this ACR server"
  value       = azurerm_container_registry.acr.login_server
}

output "blue_app_url" {
  description = "Blue Container App public URL"
  value       = "https://${azurerm_container_app.blue.latest_revision_fqdn}"
}

output "green_app_url" {
  description = "Green Container App public URL"
  value       = "https://${azurerm_container_app.green.latest_revision_fqdn}"
}

output "blob_storage_account" {
  description = "Blob storage account name"
  value       = azurerm_storage_account.storage.name
}
