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
