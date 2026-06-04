variable "name_prefix" {
  type = string

  validation {
    # Key Vault names: 3-24 chars, alphanumeric and hyphens
    condition     = can(regex("^[a-zA-Z0-9-]{3,24}$", var.name_prefix))
    error_message = "Key Vault name prefix must be 3-24 alphanumeric/hyphen characters."
  }
}

variable "location" { type = string }
variable "resource_group_name" { type = string }

variable "soft_delete_days" {
  type    = number
  default = 7
}

variable "enable_purge_protection" {
  description = "Enable purge protection (cannot be disabled once enabled)"
  type        = bool
  default     = false # Keep false for homelab so you can delete/recreate freely
}

variable "allowed_ip_rules" {
  description = "IP addresses allowed through the Key Vault firewall"
  type        = list(string)
  default     = []
}

variable "reader_principal_ids" {
  description = "Object IDs of managed identities granted read access"
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}