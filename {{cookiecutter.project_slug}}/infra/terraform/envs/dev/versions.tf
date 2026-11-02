terraform {
  required_version = ">= 1.11, < 2.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.11"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
  }

  # Account details come from ../../backend.hcl (written by bootstrap):
  #   terraform init -backend-config=../../backend.hcl
  backend "azurerm" {
    key = "dev.tfstate"
  }
}

# Subscription: ARM_SUBSCRIPTION_ID. Resource providers are registered by bootstrap/.
provider "azurerm" {
  features {}
  storage_use_azuread             = true
  resource_provider_registrations = "none"
}
