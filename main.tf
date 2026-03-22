
# ─────────────────────────────────────────
# VARIABLES
# ─────────────────────────────────────────
variable "admin_password" {
  description = "Password for VM login (azureuser)"
  type        = string
  sensitive   = true
}

variable "location" {
  default = "japaneast"
  type    = string
}

variable "rg_name" {
  default = "shivalik-rg"
  type    = string
}

# ─────────────────────────────────────────
# RESOURCE GROUP
# ─────────────────────────────────────────
resource "azurerm_resource_group" "rg" {
  location = var.location
  name     = var.rg_name
}

# ─────────────────────────────────────────
# NSG — SSH + HTTP
# ─────────────────────────────────────────
resource "azurerm_network_security_group" "nsg" {
  name                = "shivalik-nsg"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "allow-ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-http"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  depends_on = [azurerm_resource_group.rg]
}

# ─────────────────────────────────────────
# VNET — 1 VNet, 2 VM subnets + 1 AGW subnet
# ─────────────────────────────────────────
resource "azurerm_virtual_network" "vnet" {
  name                = "shivalik-vnet"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.5.0.0/16"]

  depends_on = [azurerm_resource_group.rg]
}

resource "azurerm_subnet" "subnet1" {
  name                 = "shivalik-subnet1"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.5.1.0/24"]

  depends_on = [azurerm_virtual_network.vnet]
}

resource "azurerm_subnet" "subnet2" {
  name                 = "shivalik-subnet2"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.5.2.0/24"]

  depends_on = [azurerm_virtual_network.vnet]
}

resource "azurerm_subnet" "agw_subnet" {
  name                 = "shivalik-agw-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.5.3.0/24"]

  depends_on = [azurerm_virtual_network.vnet]
}

# ─────────────────────────────────────────
# PUBLIC IPs
# ─────────────────────────────────────────
resource "azurerm_public_ip" "pip" {
  name                = "shivalik-pip"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"

  depends_on = [azurerm_resource_group.rg]
}

resource "azurerm_public_ip" "agw_pip" {
  name                = "medical-chatbot-agw-pip"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"

  depends_on = [azurerm_resource_group.rg]
}

# ─────────────────────────────────────────
# NIC + NSG Association
# ─────────────────────────────────────────
resource "azurerm_network_interface" "nic" {
  name                = "shivalik-nic"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet1.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }

  depends_on = [
    azurerm_subnet.subnet1,
    azurerm_public_ip.pip
  ]
}

resource "azurerm_network_interface_security_group_association" "nic_nsg" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# ─────────────────────────────────────────
# LINUX VM — Japan East | Standard_DC4ds_v3
# nginx installed on first boot via custom_data
# ─────────────────────────────────────────
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "shivalik-vm"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  size                = "Standard_DC4ds_v3"

  admin_username                  = "azureuser"
  admin_password                  = var.admin_password
  disable_password_authentication = false

  custom_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y nginx
    systemctl enable nginx
    systemctl start nginx
    echo "<h1>shivalik-vm | Japan East | medical-chatbot</h1>" > /var/www/html/index.html
  EOF
  )

  network_interface_ids = [azurerm_network_interface.nic.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  depends_on = [azurerm_network_interface.nic]
}

# ─────────────────────────────────────────
# AZURE CONTAINER REGISTRY (ACR)
# ─────────────────────────────────────────
resource "azurerm_container_registry" "acr" {
  name                = "medchatbotacrv2prod"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  sku                 = "Basic"
  admin_enabled       = true

  depends_on = [azurerm_resource_group.rg]
}

# ─────────────────────────────────────────
# STORAGE ACCOUNT + BLOB CONTAINER
# ─────────────────────────────────────────
resource "azurerm_storage_account" "storage" {
  name                     = "ReactAPKstorage"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  depends_on = [azurerm_resource_group.rg]
}

resource "azurerm_storage_container" "endpoints" {
  name                  = "endpoints"
  storage_account_name  = azurerm_storage_account.storage.name
  container_access_type = "private"
}

# ─────────────────────────────────────────
# LOG ANALYTICS WORKSPACE
# Required by Container Apps Environment
# ─────────────────────────────────────────
resource "azurerm_log_analytics_workspace" "law" {
  name                = "medical-chatbot-law"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  depends_on = [azurerm_resource_group.rg]
}

# ─────────────────────────────────────────
# CONTAINER APPS ENVIRONMENT
# ─────────────────────────────────────────
resource "azurerm_container_app_environment" "env" {
  name                       = "medical-chatbot-env"
  location                   = var.location
  resource_group_name        = azurerm_resource_group.rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  depends_on = [azurerm_log_analytics_workspace.law]
}

# ─────────────────────────────────────────
# BLUE CONTAINER APP
# ─────────────────────────────────────────
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

# ─────────────────────────────────────────
# GREEN CONTAINER APP
# The FQDN of this app is used as the AGW
# backend pool target (see backend_address_pool below)
# ─────────────────────────────────────────
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

# ─────────────────────────────────────────
# LOCAL VALUES
# ─────────────────────────────────────────
locals {
  agw_fe_ip_config  = "agw-fe-ip-config"
  agw_fe_port       = "agw-fe-port-80"
  agw_be_pool       = "greenBackendPool"
  agw_be_settings   = "chatbot-backend-settings"
  agw_http_listener = "agw-http-listener"
  agw_routing_rule  = "chatbot-rule"
  agw_probe         = "chatbot-custom-probe"
}

# ─────────────────────────────────────────
# APPLICATION GATEWAY
# Backend pool uses GREEN container app FQDN
# ─────────────────────────────────────────
resource "azurerm_application_gateway" "agw" {
  name                = "medical-chatbot-agw"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  sku {
    name = "Standard_v2"
    tier = "Standard_v2"
  }

  autoscale_configuration {
    min_capacity = 1
    max_capacity = 3
  }

  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101"
  }

  gateway_ip_configuration {
    name      = "agw-gateway-ip-config"
    subnet_id = azurerm_subnet.agw_subnet.id
  }

  frontend_ip_configuration {
    name                 = local.agw_fe_ip_config
    public_ip_address_id = azurerm_public_ip.agw_pip.id
  }

  frontend_port {
    name = local.agw_fe_port
    port = 80
  }

  # ─────────────────────────────────────────
  # BACKEND POOL — GREEN container app FQDN
  #
  # CHANGED from ip_addresses to fqdns.
  # latest_revision_fqdn returns the hostname like:
  # medical-chatbot-green.kindbeach-abc123.japaneast.azurecontainerapps.io
  #
  # AGW resolves this via DNS on every request —
  # no hardcoded IPs, works even if container scales or restarts.
  # ─────────────────────────────────────────
  backend_address_pool {
    name  = local.agw_be_pool
    fqdns = [azurerm_container_app.green.ingress[0].fqdn]
  }

  # ─────────────────────────────────────────
  # BACKEND HTTP SETTINGS
  # port 8000 — matches green container app target_port
  # pick_host_name_from_backend_address = true
  # sends the container app FQDN as the HTTP Host header,
  # which Container Apps requires for correct routing.
  # ─────────────────────────────────────────
  backend_http_settings {
    name                                = local.agw_be_settings
    cookie_based_affinity               = "Disabled"
    port                                = 8000
    protocol                            = "Http"
    request_timeout                     = 30
    pick_host_name_from_backend_address = true
    probe_name                          = local.agw_probe
  }

  probe {
    name                                      = local.agw_probe
    protocol                                  = "Http"
    path                                      = "/"
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true
  }

  http_listener {
    name                           = local.agw_http_listener
    frontend_ip_configuration_name = local.agw_fe_ip_config
    frontend_port_name             = local.agw_fe_port
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = local.agw_routing_rule
    rule_type                  = "Basic"
    priority                   = 100
    http_listener_name         = local.agw_http_listener
    backend_address_pool_name  = local.agw_be_pool
    backend_http_settings_name = local.agw_be_settings
  }

  depends_on = [
    azurerm_subnet.agw_subnet,
    azurerm_public_ip.agw_pip,
    azurerm_container_app.green
  ]
}

# ─────────────────────────────────────────
# OUTPUTS
# ─────────────────────────────────────────
output "vm_public_ip" {
  description = "VM public IP (SSH access)"
  value       = azurerm_public_ip.pip.ip_address
}

output "agw_public_ip" {
  description = "AGW public IP — all HTTP traffic enters here"
  value       = azurerm_public_ip.agw_pip.ip_address
}

output "acr_login_server" {
  description = "Push your Docker image to this ACR"
  value       = azurerm_container_registry.acr.login_server
}

output "blue_app_fqdn" {
  description = "Blue Container App FQDN"
  value       = azurerm_container_app.blue.ingress[0].fqdn
}

output "green_app_fqdn" {
  description = "Green Container App FQDN — used as AGW backend target"
  value       = azurerm_container_app.green.ingress[0].fqdn
}

output "blob_storage_account" {
  description = "Blob storage account name"
  value       = azurerm_storage_account.storage.name
}
