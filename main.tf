# ─────────────────────────────────────────
# VARIABLES
# ─────────────────────────────────────────
variable "admin_password" {
  description = "Password for VM login (azureuser)"
  type        = string 
  sensitive   = true
}

variable "location" {
  default = "australiaeast"
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
# NSG — with SSH rule
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
}

# ─────────────────────────────────────────
# VNET — single VNet with address space
# ─────────────────────────────────────────
resource "azurerm_virtual_network" "vnet" {
  name                = "shivalik-vnet"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.5.0.0/16"]
}

# ─────────────────────────────────────────
# SUBNET 1 — primary subnet for the VM
# ─────────────────────────────────────────
resource "azurerm_subnet" "subnet1" {
  name                 = "shivalik-subnet1"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.5.1.0/24"]
}

# ─────────────────────────────────────────
# SUBNET 2 — secondary subnet (same VNet)
# ─────────────────────────────────────────
resource "azurerm_subnet" "subnet2" {
  name                 = "shivalik-subnet2"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.5.2.0/24"]
}

# ─────────────────────────────────────────
# PUBLIC IP — VM
# ─────────────────────────────────────────
resource "azurerm_public_ip" "pip" {
  name                = "shivalik-pip"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# ─────────────────────────────────────────
# NIC — VM NIC attached to subnet1 with public IP
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
}

# ─────────────────────────────────────────
# NSG → NIC Association
# ─────────────────────────────────────────
resource "azurerm_network_interface_security_group_association" "nic_nsg" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# ─────────────────────────────────────────
# LINUX VM — Australia East | 4 vCPU (Standard_D4ads_v5)
# ─────────────────────────────────────────
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "shivalik-vm"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  size                = "Standard_D4ads_v5"   # 4 vCPU, 16 GB RAM

  admin_username                  = "azureuser"
  admin_password                  = var.admin_password
  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.nic.id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}
