locals {
  name_prefix         = "${var.project_name}-${var.environment}"
  resource_group_name = "rg-${local.name_prefix}"
  unique_suffix = substr(md5("${var.project_name}${var.environment}"), 0, 6)
  
  common_tags = merge(
    {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "Terraform"
      Owner       = "homelab"
    },
    var.tags
  )

  vm_sku_map = {
    dev     = "Standard_D2as_v7"
    staging = "Standard_D2as_v7"
    prod    = "Standard_D4as_v7"
}

  vm_sku = local.vm_sku_map[var.environment]
}