resource "azurerm_resource_group" "resgroup" {
  name     = "resgroup"
  location = "West Europe"
}

resource "azurerm_storage_account" "stacc" {
  name                     = "newstorage123"
  resource_group_name      = azurerm_resource_group.resgroup.name
  location                 = azurerm_resource_group.resgroup.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
}

resource "azurerm_storage_container" "container" {
  name                 = "container123"
  storage_account_name = azurerm_storage_account.stacc.name
}
