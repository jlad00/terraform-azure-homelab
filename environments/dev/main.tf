terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }

  backend "azurerm" {
    # Credentials come from ARM_* environment variables
  }
}

provider "azurerm" {
  features {}
  skip_provider_registration = true
  # Credentials come from ARM_* environment variables
  # Never hardcode credentials here
}

resource "azurerm_resource_group" "primary" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

module "networking" {
  source = "../../modules/networking"

  name_prefix         = local.name_prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.primary.name
  tags                = local.common_tags

  vnet_address_space = ["10.10.0.0/16"]

  subnets = {
    "snet-app" = {
      address_prefix = "10.10.1.0/24"
    }
    "snet-data" = {
      address_prefix = "10.10.2.0/24"
    }
  }

  nsg_rules = [
    {
      name                       = "allow-https-inbound"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "443"
      source_address_prefix      = "Internet"
      destination_address_prefix = "VirtualNetwork"
    },
    {
      name                       = "deny-http-inbound"
      priority                   = 200
      direction                  = "Inbound"
      access                     = "Deny"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "80"
      source_address_prefix      = "Internet"
      destination_address_prefix = "VirtualNetwork"
    }
  ]
}

module "networking_mgmt" {
  source = "../../modules/networking"

  name_prefix         = "${local.name_prefix}-mgmt"
  location            = var.location
  resource_group_name = azurerm_resource_group.primary.name
  tags                = merge(local.common_tags, { NetworkTier = "management" })

  vnet_address_space = ["10.20.0.0/16"]

  subnets = {
    "snet-mgmt" = {
      address_prefix = "10.20.1.0/24"
    }
    "snet-bastion" = {
      address_prefix = "10.20.2.0/24"
    }
  }

  nsg_rules = [
    {
      name                       = "allow-ssh-inbound"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "22"
      source_address_prefix      = "10.10.0.0/16" # only allow from app network
      destination_address_prefix = "VirtualNetwork"
    }
  ]
}

module "keyvault" {
  source = "../../modules/keyvault"

  name_prefix         = "kv-hl-dev-${local.unique_suffix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.primary.name
  tags                = local.common_tags

  # Allow your home IP through the firewall
  allowed_ip_rules = ["75.84.241.3/32"]
}

resource "azurerm_storage_account" "state_backend" {
  name                             = "sttfstate6a9b3db0"
  resource_group_name              = "rg-terraform-state"
  location                         = "eastus"
  account_tier                     = "Standard"
  account_replication_type         = "LRS"
  min_tls_version                  = "TLS1_2"
  allow_nested_items_to_be_public  = false
  cross_tenant_replication_enabled = false
}

