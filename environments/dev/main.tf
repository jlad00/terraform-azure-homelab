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

resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

module "networking" {
  source = "../../modules/networking"

  name_prefix         = local.name_prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
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
  resource_group_name = azurerm_resource_group.main.name
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

variable "ssh_public_key" {
  description = "SSH public key for VM admin access"
  type        = string
  sensitive   = true
}

module "app_vm" {
  source = "../../modules/compute"

  name_prefix         = "${local.name_prefix}-app"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = module.networking.subnet_ids["snet-app"]
  vm_size             = local.vm_sku
  ssh_public_key      = var.ssh_public_key
  tags                = local.common_tags

  depends_on = [module.networking]
}

module "keyvault" {
  source = "../../modules/keyvault"

  name_prefix         = "kv-hl-dev-${local.unique_suffix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags

  # Grant the VM's managed identity read access
  reader_principal_ids = [module.app_vm.principal_id]

  # Allow your home IP through the firewall
  allowed_ip_rules = ["75.84.241.3/32"]
}