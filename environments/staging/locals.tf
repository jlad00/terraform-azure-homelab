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