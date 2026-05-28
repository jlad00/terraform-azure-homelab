variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "eastus"

  validation {
    condition = contains([
      "eastus", "eastus2", "westus", "westus2",
      "centralus", "northeurope", "westeurope"
    ], var.location)
    error_message = "Location must be an approved Azure region."
  }
}

variable "project_name" {
  description = "Short project identifier, used in resource names (3-8 chars, lowercase alphanumeric)"
  type        = string
  default     = "homelab"

  validation {
    condition     = can(regex("^[a-z0-9]{3,8}$", var.project_name))
    error_message = "Project name must be 3-8 lowercase alphanumeric characters."
  }
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
