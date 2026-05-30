locals {
  # Standardized naming prefix: {project}-{env}
  name_prefix = "${var.project_name}-${var.environment}"

  # Common tags merged with caller-supplied tags
  common_tags = merge(
    {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "Terraform"
      Owner       = "homelab"
    },
    var.tags
  )

  # Resource group name follows CAF pattern
  resource_group_name = "rg-${local.name_prefix}"
}

locals {
  # If you were using workspaces, you'd do this:
  # workspace_name_prefix = "${var.project_name}-${terraform.workspace}"

  # But since we use directories, we use tfvars-controlled environment:
  name_prefix = "${var.project_name}-${var.environment}"

  # Environment-specific sizing (mirrors real company tiering)
  vm_sku_map = {
    dev     = "Standard_B1s"
    staging = "Standard_B2s"
    prod    = "Standard_D2s_v3"
  }

  # Select the right SKU for this environment
  vm_sku = local.vm_sku_map[var.environment]
}