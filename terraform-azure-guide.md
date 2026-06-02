# Terraform on Azure: Skills Sharpening Guide
### A Homelab-to-Enterprise Workflow for Experienced Practitioners

> **Your starting point:** You have hands-on Terraform experience with the vSphere provider. This guide bridges that knowledge into Azure-native patterns, enterprise conventions, and CI/CD-ready workflows — the kind of Terraform used in real company environments.

> **Shell note:** All CLI commands in this guide use **PowerShell** (pwsh or Windows PowerShell 5.1). Use PowerShell for all `az` and setup commands. Terraform commands work identically in PowerShell or Git Bash. GitHub Actions workflows run on `ubuntu-latest` and use bash internally — that's expected and correct.

---

## How to Use This Guide

Each module builds on the previous. Complete them in order. Every module has:
- **Context** — why this matters in a real company
- **Concepts** — what you need to know
- **Exercise** — hands-on work in your homelab/Azure account
- **Validation** — how to confirm you did it right
- **Stretch goals** — push further if you want

**Time estimate:** ~2–4 hours per module, 8 modules total.

---

## Prerequisites & Account Setup

### Azure Free Account
1. Sign up at [portal.azure.com](https://portal.azure.com) — you get $200 credit for 30 days + always-free services
2. Install the Azure CLI: `winget install Microsoft.AzureCLI`
3. Install PowerShell 7 (recommended): `winget install Microsoft.PowerShell`
4. Log in: `az login`
5. Note your Subscription ID: `az account show --query id -o tsv`

### Tooling Checklist
```powershell
# Verify each is installed
terraform version       # >= 1.6.0 recommended
az version              # Azure CLI
git --version           # for VCS exercises
$PSVersionTable.PSVersion  # PowerShell version
```

### Repository Structure (use this for all exercises)
```
terraform-azure-homelab/
├── modules/
│   ├── networking/
│   ├── compute/
│   └── storage/
├── environments/
│   ├── dev/
│   ├── staging/
│   └── prod/
├── .github/
│   └── workflows/
├── .gitignore
├── .terraform-version    # for tfenv/tofuenv
└── README.md
```

Create this structure now — you'll populate it throughout the guide.

```powershell
# Create directory structure
$dirs = @(
    "terraform-azure-homelab/modules/networking",
    "terraform-azure-homelab/modules/compute",
    "terraform-azure-homelab/modules/storage",
    "terraform-azure-homelab/environments/dev",
    "terraform-azure-homelab/environments/staging",
    "terraform-azure-homelab/environments/prod",
    "terraform-azure-homelab/.github/workflows"
)
$dirs | ForEach-Object { New-Item -ItemType Directory -Force -Path $_ }

cd terraform-azure-homelab
git init
```

---

## Module 1: Provider Configuration & Remote State

**The vSphere gap:** In vSphere you probably stored state locally or on a shared filesystem. In a company environment, state lives in a managed backend (Azure Blob Storage, Terraform Cloud, S3). This is non-negotiable — local state is a career-limiting practice in teams.

### Concepts

**State backends** store `terraform.tfstate` remotely so teams can collaborate without conflicts. Azure Blob Storage is the natural choice for Azure workloads.

**Provider authentication** in a company happens via Service Principals (not your personal login). You'll set this up now as it mirrors real-world practice.

**Partial configuration** lets you define the backend block without hardcoding secrets, passing them at `terraform init` time — critical for CI/CD.

### Exercise 1A: Bootstrap the State Backend

First, create the storage account that will hold your Terraform state. Do this step *manually* (via CLI or portal) — it's the one thing you can't manage with Terraform before state exists.

```powershell
# Set variables
$RESOURCE_GROUP  = "rg-terraform-state"
$STORAGE_ACCOUNT = "sttfstate$(Get-Random -Maximum 99999999)"   # must be globally unique
$CONTAINER       = "tfstate"
$LOCATION        = "eastus"

# Create the resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create the storage account
az storage account create `
  --name $STORAGE_ACCOUNT `
  --resource-group $RESOURCE_GROUP `
  --location $LOCATION `
  --sku Standard_LRS `
  --encryption-services blob `
  --min-tls-version TLS1_2 `
  --allow-blob-public-access false

# Create the container
az storage container create `
  --name $CONTAINER `
  --account-name $STORAGE_ACCOUNT `
  --auth-mode login

Write-Host "Storage Account: $STORAGE_ACCOUNT"
```

> **Note your storage account name** — you'll need it in Exercise 1C.

### Exercise 1B: Create a Service Principal

```powershell
# Get your subscription ID
$SUBSCRIPTION_ID = az account show --query id -o tsv

# Create SP with Contributor role scoped to your subscription
az ad sp create-for-rbac `
  --name "sp-terraform-homelab" `
  --role Contributor `
  --scopes /subscriptions/$SUBSCRIPTION_ID

# Output will show: appId, displayName, password, tenant
# Save these — the password won't be shown again
```

Set environment variables for your current session. Save these to a script you can re-run (add it to `.gitignore` — never commit credentials):

```powershell
# Create a file called Set-TerraformEnv.ps1 (add to .gitignore)
$env:ARM_CLIENT_ID       = "20785f58-f1bf-4d06-abf3-217c3a105d4c"
$env:ARM_CLIENT_SECRET   = "Duv8Q~6Z13AHLlN_QjcMX~GK-7CxByKKp4w3rbg9"
$env:ARM_TENANT_ID       = "b84b1ace-77a2-480d-a09e-0f7b6e3bcc43"
$env:ARM_SUBSCRIPTION_ID = "fab53862-2845-4dd0-9873-fcae704de157"

# Verify they are set
Write-Host "Client ID: $env:ARM_CLIENT_ID"
Write-Host "Tenant ID: $env:ARM_TENANT_ID"
Write-Host "Sub ID:    $env:ARM_SUBSCRIPTION_ID"
```

> **Important:** `$env:` variables only persist for your current PowerShell session. Re-run `Set-TerraformEnv.ps1` any time you open a new terminal before running Terraform commands.

### Exercise 1C: Write Provider and Backend Configuration

Create `environments/dev/main.tf`:

```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "<your-storage-account-name>"
    container_name       = "tfstate"
    key                  = "dev/terraform.tfstate"
    # Credentials come from ARM_* environment variables
  }
}

provider "azurerm" {
  features {}
  # Credentials come from ARM_* environment variables
  # Never hardcode credentials here
}
```

Initialize and verify:

```powershell
cd environments/dev
terraform init
terraform workspace list   # Should show: * default
```

### Validation
- `terraform init` succeeds without errors
- In the Azure portal, confirm the `tfstate` container exists in your storage account
- Run `terraform plan` — it should show "No changes" with empty config

### Stretch Goals
- Add a `backend_config.hcl` file and use `terraform init -backend-config=backend_config.hcl` to separate config from code
- Lock the state file manually via the portal (Storage Account → Containers → tfstate → select the blob → Acquire Lease) and observe what happens when you try to `plan`

---

## Module 2: Variables, Locals, and Outputs

**The vSphere gap:** Variable hygiene matters more on public cloud because you're paying for what you deploy. Misconfigured SKUs or regions can be costly mistakes. Enterprise Terraform uses strict variable typing, validation rules, and consistent naming conventions.

### Concepts

**Variable types** — always declare explicit types. Never use untyped variables in shared code.

**Validation blocks** — enforce constraints at plan time rather than letting Azure API return cryptic errors.

**Locals** — computed values derived from variables; avoid repeating logic.

**Naming conventions** — Azure has a well-documented naming convention (CAF — Cloud Adoption Framework). You'll use a simplified version here.

### Exercise 2A: Variables File

Create `environments/dev/variables.tf`:

```hcl
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
```

Create `environments/dev/locals.tf`:

```hcl
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
```

Create `environments/dev/terraform.tfvars`:

```hcl
environment  = "dev"
location     = "eastus"
project_name = "homelab"

tags = {
  CostCenter = "homelab-personal"
  Repo       = "terraform-azure-homelab"
}
```

Create `environments/dev/outputs.tf`:

```hcl
output "resource_group_name" {
  description = "Name of the primary resource group"
  value       = azurerm_resource_group.main.name
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}
```

Add to `environments/dev/main.tf`:

```hcl
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}
```

### Validation

```powershell
terraform plan    # Should show resource group to be created with all expected tags
```

- Try setting `environment = "qa"` in tfvars — the validation error should fire at plan time
- Try setting `project_name = "my project"` — validation should reject the space

```powershell
# Use the Terraform console to interactively test expressions
terraform console
# Then type: local.common_tags
# Type: exit to quit
```

### Stretch Goals
- Add a `sensitive = true` variable for a secret value and observe how it behaves in plan output
- Explore `terraform console` further — test `local.name_prefix`, `var.environment`, etc.

---

## Module 3: Reusable Modules

**The vSphere gap:** Copying and pasting resource blocks between environments is a company anti-pattern. Modules are the primary unit of reuse in enterprise Terraform. You write once, call many times with different inputs.

### Concepts

**Module structure** — inputs (variables), outputs, and resources. No provider blocks inside modules (they inherit from the root).

**Module versioning** — in companies, modules live in a registry or git repo with tags. You'll simulate this with local paths, then understand how to reference remote sources.

**Module interface design** — keep modules opinionated but flexible. Don't expose every possible resource argument; expose what callers actually need.

### Exercise 3A: Write a Networking Module

Create `modules/networking/main.tf`:

```hcl
resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.vnet_address_space
  tags                = var.tags
}

resource "azurerm_subnet" "subnets" {
  for_each = var.subnets

  name                 = each.key
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [each.value.address_prefix]

  dynamic "delegation" {
    for_each = lookup(each.value, "delegation", null) != null ? [each.value.delegation] : []

    content {
      name = delegation.value.name
      service_delegation {
        name    = delegation.value.service_name
        actions = delegation.value.actions
      }
    }
  }
}

resource "azurerm_network_security_group" "this" {
  name                = "nsg-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "this" {
  for_each = var.subnets

  subnet_id                 = azurerm_subnet.subnets[each.key].id
  network_security_group_id = azurerm_network_security_group.this.id
}
```

Create `modules/networking/variables.tf`:

```hcl
variable "name_prefix" {
  description = "Naming prefix for all resources in this module"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to deploy into"
  type        = string
}

variable "vnet_address_space" {
  description = "CIDR blocks for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnets" {
  description = "Map of subnet configurations"
  type = map(object({
    address_prefix = string
    delegation = optional(object({
      name         = string
      service_name = string
      actions      = list(string)
    }))
  }))
  default = {}
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
```

Create `modules/networking/outputs.tf`:

```hcl
output "vnet_id" {
  description = "Resource ID of the virtual network"
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.this.name
}

output "subnet_ids" {
  description = "Map of subnet name to subnet resource ID"
  value       = { for k, v in azurerm_subnet.subnets : k => v.id }
}

output "nsg_id" {
  description = "Resource ID of the network security group"
  value       = azurerm_network_security_group.this.id
}
```

### Exercise 3B: Call the Module from Dev Environment

Add to `environments/dev/main.tf`:

```hcl
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
}
```

Add to `environments/dev/outputs.tf`:

```hcl
output "vnet_id" {
  description = "Virtual network resource ID"
  value       = module.networking.vnet_id
}

output "subnet_ids" {
  description = "Map of subnet IDs"
  value       = module.networking.subnet_ids
}
```

```powershell
terraform init    # Re-init to pull in the new module
terraform plan    # Should show VNet, subnets, NSG, associations
terraform apply
```

### Validation

```powershell
terraform output                          # Shows expected values
terraform state list                      # Shows module-namespaced resources
                                          # e.g. module.networking.azurerm_virtual_network.this
```

- Resources appear in Azure portal under the correct resource group

### Stretch Goals
- Add an NSG rule variable to the module (e.g., `nsg_rules = list(object(...))`) with a `dynamic` block
- Create a second call to the same module with different parameters to simulate a separate "management" network

---

## Module 4: Workspaces and Multi-Environment Strategy

**The vSphere gap:** Terraform workspaces let you manage multiple deployment targets from a single configuration. But they have limitations — this module teaches both the pattern *and* when to abandon it in favor of a directory-per-environment approach (which is what most companies actually do at scale).

### Concepts

**Workspaces vs. directories:** Workspaces share the same code and use `terraform.workspace` to branch behavior. Directory-per-environment duplicates code but is much clearer. Most enterprises use **directories with shared modules** (what you've been building) rather than workspaces.

**`terraform.workspace` interpolation** — useful for naming to avoid clashes, but overused.

**When workspaces make sense:** Ephemeral environments (feature branch deploys), PR preview environments, or when environments are truly identical except for scale.

### Exercise 4A: Workspace-Based Naming

Add this to your dev `locals.tf` to see how workspaces would influence naming:

```hcl
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
```

### Exercise 4B: Simulate a Staging Environment

```powershell
# Copy the dev environment structure to staging
Copy-Item environments/dev/*.tf environments/staging/
Copy-Item environments/dev/terraform.tfvars environments/staging/
```

Edit `environments/staging/terraform.tfvars`:

```hcl
environment  = "staging"
location     = "eastus"
project_name = "homelab"

tags = {
  CostCenter = "homelab-personal"
  Repo       = "terraform-azure-homelab"
}
```

Edit `environments/staging/main.tf` — change only the state key:

```hcl
backend "azurerm" {
  resource_group_name  = "rg-terraform-state"
  storage_account_name = "<your-storage-account-name>"
  container_name       = "tfstate"
  key                  = "staging/terraform.tfstate"   # Different key from dev!
}
```

```powershell
cd environments/staging
terraform init
terraform plan    # Shows staging resources without touching dev state
```

### Exercise 4C: Understand State Isolation

```powershell
# From dev environment
cd environments/dev
terraform state list

# From staging environment
cd environments/staging
terraform state list    # Completely separate state
```

### Validation
- Dev and staging are two separate state files in blob storage (check the portal — you'll see `dev/terraform.tfstate` and `staging/terraform.tfstate`)
- Applying staging doesn't affect dev resources
- Resource names in Azure have `-dev` vs `-staging` suffixes

### Stretch Goals
- Run `terraform destroy` for staging and observe what happens to dev (nothing)
- Look up Terraform's `moved` block and understand when you'd use it when refactoring module structure

---

## Module 5: Compute Resources & Data Sources

**The vSphere gap:** Instead of vSphere VMs and templates, you'll work with Azure VMs and use data sources to reference existing infrastructure — a critical pattern for working in shared Azure environments without owning everything.

### Concepts

**Data sources** — read existing infrastructure without managing it. Essential for referencing resources owned by other teams (shared VNets, Key Vaults, DNS zones).

**`depends_on`** — explicit dependency when Terraform can't infer it from reference chains.

**`lifecycle` blocks** — control create-before-destroy, prevent accidental deletion, and ignore drift in managed fields.

### Exercise 5A: Add a Compute Module

Create `modules/compute/main.tf`:

```hcl
# Look up the latest Ubuntu 22.04 image — don't hardcode image versions
data "azurerm_platform_image" "ubuntu" {
  location  = var.location
  publisher = "Canonical"
  offer     = "0001-com-ubuntu-server-jammy"
  sku       = "22_04-lts-gen2"
}

resource "azurerm_linux_virtual_machine" "this" {
  name                = "vm-${var.name_prefix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = var.vm_size
  admin_username      = var.admin_username
  tags                = var.tags

  # Disable password auth — SSH keys only, always
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  network_interface_ids = [azurerm_network_interface.this.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_type
  }

  source_image_reference {
    publisher = data.azurerm_platform_image.ubuntu.publisher
    offer     = data.azurerm_platform_image.ubuntu.offer
    sku       = data.azurerm_platform_image.ubuntu.sku
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"   # Always use managed identity when possible
  }

  lifecycle {
    # Don't destroy/recreate if the image changes — update separately
    ignore_changes = [source_image_reference]

    # Uncomment in prod to prevent accidental deletion
    # prevent_destroy = true
  }
}

resource "azurerm_network_interface" "this" {
  name                = "nic-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}
```

Create `modules/compute/variables.tf`:

```hcl
variable "name_prefix" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "subnet_id" {
  description = "Subnet to attach the VM network interface to"
  type        = string
}

variable "vm_size" {
  description = "Azure VM SKU"
  type        = string
  default     = "Standard_B1s"
}

variable "admin_username" {
  description = "Local admin username"
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key" {
  description = "SSH public key for admin access"
  type        = string
  sensitive   = true
}

variable "os_disk_type" {
  description = "Storage type for OS disk"
  type        = string
  default     = "Standard_LRS"

  validation {
    condition     = contains(["Standard_LRS", "StandardSSD_LRS", "Premium_LRS"], var.os_disk_type)
    error_message = "OS disk type must be Standard_LRS, StandardSSD_LRS, or Premium_LRS."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

Create `modules/compute/outputs.tf`:

```hcl
output "vm_id" {
  value = azurerm_linux_virtual_machine.this.id
}

output "vm_name" {
  value = azurerm_linux_virtual_machine.this.name
}

output "principal_id" {
  description = "System-assigned managed identity principal ID"
  value       = azurerm_linux_virtual_machine.this.identity[0].principal_id
}

output "private_ip" {
  value = azurerm_network_interface.this.private_ip_address
}
```

### Exercise 5B: Generate an SSH Key and Call the Compute Module

```powershell
# Generate an SSH key pair (if you don't have one already)
ssh-keygen -t ed25519 -C "terraform-homelab" -f "$HOME\.ssh\terraform-homelab"

# Read the public key into a variable for use below
$SSH_PUBLIC_KEY = Get-Content "$HOME\.ssh\terraform-homelab.pub"
```

Add to `environments/dev/main.tf`:

```hcl
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
```

Pass the SSH key via environment variable (never in tfvars):

```powershell
# Set the TF_VAR_ variable so Terraform picks it up automatically
$env:TF_VAR_ssh_public_key = Get-Content "$HOME\.ssh\terraform-homelab.pub"

terraform plan
terraform apply
```

### Validation

```powershell
terraform output    # Shows private IP and other outputs
terraform plan      # Should show no changes (lifecycle ignore_changes working)
```

- VM appears in portal with correct size and no password authentication
- VM has a system-assigned managed identity under Identity tab in portal

### Stretch Goals
- Add a `azurerm_role_assignment` to give the VM's managed identity read access to a Key Vault
- Use a data source to reference a resource that already exists: `data "azurerm_resource_group" "existing" { name = "some-existing-rg" }`

---

## Module 6: Secrets Management & Key Vault

**The vSphere gap:** On-prem Terraform often uses hardcoded secrets or Vault. Azure's native answer is Key Vault. This module teaches the correct pattern: Terraform provisions the Key Vault and access policies, but *secrets are stored outside of Terraform state*.

### Concepts

**Never store secrets in Terraform state** — state is plaintext JSON. Even `sensitive = true` just redacts console output; the value is still in the state file.

**Key Vault + Managed Identity** — the correct pattern: VM gets an identity, Key Vault grants that identity access, the app fetches secrets at runtime.

**Data source for secrets** — if Terraform *must* read a secret (e.g., to pass a DB password to an app config), use `data "azurerm_key_vault_secret"` and mark outputs sensitive.

### Exercise 6A: Key Vault Module

Create `modules/keyvault/main.tf`:

```hcl
data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "this" {
  name                = "kv-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  tags                = var.tags

  # Soft delete and purge protection — always enable in prod
  soft_delete_retention_days = var.soft_delete_days
  purge_protection_enabled   = var.enable_purge_protection

  # Restrict network access (principle of least privilege)
  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules       = var.allowed_ip_rules
  }
}

# Grant Terraform's service principal access to manage secrets
resource "azurerm_key_vault_access_policy" "terraform_sp" {
  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = ["Get", "List", "Set", "Delete", "Recover", "Backup", "Restore", "Purge"]
}

# Grant each managed identity read access
resource "azurerm_key_vault_access_policy" "identities" {
  for_each = toset(var.reader_principal_ids)

  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = each.value

  secret_permissions = ["Get", "List"]
}
```

Create `modules/keyvault/variables.tf`:

```hcl
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
  default     = false   # Keep false for homelab so you can delete/recreate freely
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
```

Create `modules/keyvault/outputs.tf`:

```hcl
output "key_vault_id" {
  value = azurerm_key_vault.this.id
}

output "key_vault_uri" {
  value = azurerm_key_vault.this.vault_uri
}

output "key_vault_name" {
  value = azurerm_key_vault.this.name
}
```

### Exercise 6B: Wire It All Together

First, find your home public IP:

```powershell
(Invoke-WebRequest -Uri "https://ifconfig.me").Content
```

Add to `environments/dev/main.tf`:

```hcl
module "keyvault" {
  source = "../../modules/keyvault"

  name_prefix         = local.name_prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags

  # Grant the VM's managed identity read access
  reader_principal_ids = [module.app_vm.principal_id]

  # Allow your home IP through the firewall
  allowed_ip_rules = ["<your-home-ip>/32"]
}
```

After applying, add a test secret *outside of Terraform*:

```powershell
az keyvault secret set `
  --vault-name "kv-kv-hl-dev-a0e41e" `
  --name "test-secret" `
  --value "this-is-not-in-terraform-state"
```

### Validation

```powershell
# Confirm the secret exists
az keyvault secret show --vault-name kv-kv-hl-dev-a0e41e --name test-secret

# Confirm it is NOT in Terraform state (inspect the state)
terraform state show module.keyvault.azurerm_key_vault.this
# You will see vault config but no secret values
```

- Key Vault appears in portal with network restrictions
- The VM's managed identity has a read-only access policy
- The test secret exists but is NOT in `terraform.tfstate`

### Stretch Goals
- Rotate the secret value manually (`az keyvault secret set` again with a new value) and observe that `terraform plan` shows no drift — Terraform doesn't manage the secret value
- Use `data "azurerm_key_vault_secret"` to read the secret into Terraform as a sensitive output and understand why this is sometimes unavoidable and always risky

---

## Module 7: CI/CD with GitHub Actions

**The vSphere gap:** Running Terraform from a local terminal is a solo practice. Companies run Terraform from pipelines — this enforces code review before apply, maintains audit trails, and prevents "works on my machine" configuration drift.

### Concepts

**Plan in PR, Apply on merge** — the gold standard workflow. PRs trigger `plan`, reviewers see what will change, merges trigger `apply`.

**OIDC authentication** — instead of storing your Service Principal secret as a GitHub secret, you use OpenID Connect to grant GitHub short-lived tokens. This is the modern approach — no stored credentials.

**Concurrency controls** — prevent two pipeline runs from simultaneously applying to the same environment.

### Exercise 7A: Set Up OIDC Authentication

```powershell
# Create the app registration
$APP_ID = az ad app create --display-name "sp-github-terraform" --query appId -o tsv
az ad sp create --id $APP_ID

# Get the SP object ID
$SP_OBJECT_ID = az ad sp show --id $APP_ID --query id -o tsv
$SUBSCRIPTION_ID = az account show --query id -o tsv

# Assign Contributor role
az role assignment create `
  --assignee $SP_OBJECT_ID `
  --role Contributor `
  --scope /subscriptions/$SUBSCRIPTION_ID

# Grant access to the state storage account
$STORAGE_ID = az storage account show `
  -n sttfstate6a9b3db0 `
  -g rg-terraform-state `
  --query id -o tsv

az role assignment create `
  --assignee $SP_OBJECT_ID `
  --role "Storage Blob Data Contributor" `
  --scope $STORAGE_ID
```

Configure federated credentials for GitHub OIDC:

```powershell
# Replace with your GitHub username and repo name
$GITHUB_ORG  = "jlad00"
$REPO_NAME   = "terraform-azure-homelab"

# Federated credential for main branch (apply)
$mainCred = @{
  name      = "github-main-branch"
  issuer    = "https://token.actions.githubusercontent.com"
  subject   = "repo:${GITHUB_ORG}/${REPO_NAME}:ref:refs/heads/main"
  audiences = @("api://AzureADTokenExchange")
} | ConvertTo-Json

az ad app federated-credential create --id $APP_ID --parameters $mainCred

# Federated credential for pull requests (plan)
$prCred = @{
  name      = "github-pull-requests"
  issuer    = "https://token.actions.githubusercontent.com"
  subject   = "repo:${GITHUB_ORG}/${REPO_NAME}:pull_request"
  audiences = @("api://AzureADTokenExchange")
} | ConvertTo-Json

az ad app federated-credential create --id $APP_ID --parameters $prCred

# Print values you'll need as GitHub secrets
Write-Host "AZURE_CLIENT_ID:       $APP_ID"
Write-Host "AZURE_TENANT_ID:       $(az account show --query tenantId -o tsv)"
Write-Host "AZURE_SUBSCRIPTION_ID: $SUBSCRIPTION_ID"
```

Add these as GitHub repository secrets (Settings → Secrets and variables → Actions → New repository secret):
- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `SSH_PUBLIC_KEY` — contents of your `terraform-homelab.pub` file

```powershell
# Get the public key content to paste into GitHub secrets
Get-Content "$HOME\.ssh\terraform-homelab.pub"
```

### Exercise 7B: Write the Pipeline

Create `.github/workflows/terraform.yml`:

```yaml
name: Terraform

on:
  push:
    branches: [main]
    paths:
      - 'environments/**'
      - 'modules/**'
  pull_request:
    branches: [main]
    paths:
      - 'environments/**'
      - 'modules/**'

permissions:
  id-token: write       # Required for OIDC
  contents: read
  pull-requests: write  # Required to post plan comments

env:
  TF_VERSION: "1.7.0"
  WORKING_DIR: environments/dev

# Prevent concurrent runs on the same environment
concurrency:
  group: terraform-dev
  cancel-in-progress: false  # Don't cancel — let apply finish

jobs:
  terraform-plan:
    name: Plan
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Azure Login (OIDC)
        uses: azure/login@v1
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Terraform Init
        working-directory: ${{ env.WORKING_DIR }}
        run: terraform init
        env:
          ARM_USE_OIDC: true
          ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
          ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
          ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Terraform Format Check
        working-directory: ${{ env.WORKING_DIR }}
        run: terraform fmt -check -recursive

      - name: Terraform Validate
        working-directory: ${{ env.WORKING_DIR }}
        run: terraform validate

      - name: Terraform Plan
        id: plan
        working-directory: ${{ env.WORKING_DIR }}
        run: |
          terraform plan -no-color -out=tfplan 2>&1 | tee plan_output.txt
          echo "plan_exit_code=${PIPESTATUS[0]}" >> $GITHUB_OUTPUT
        env:
          ARM_USE_OIDC: true
          ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
          ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
          ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
          TF_VAR_ssh_public_key: ${{ secrets.SSH_PUBLIC_KEY }}

      - name: Post Plan to PR
        if: github.event_name == 'pull_request'
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const plan = fs.readFileSync('${{ env.WORKING_DIR }}/plan_output.txt', 'utf8');
            const truncated = plan.length > 65000 ? plan.substring(0, 65000) + '\n... truncated ...' : plan;

            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: `## Terraform Plan — \`dev\`\n\`\`\`hcl\n${truncated}\n\`\`\``
            });

  terraform-apply:
    name: Apply
    runs-on: ubuntu-latest
    needs: terraform-plan
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    environment: dev   # Requires GitHub Environment approval if configured

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Azure Login (OIDC)
        uses: azure/login@v1
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Terraform Init
        working-directory: ${{ env.WORKING_DIR }}
        run: terraform init
        env:
          ARM_USE_OIDC: true
          ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
          ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
          ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Terraform Apply
        working-directory: ${{ env.WORKING_DIR }}
        run: terraform apply -auto-approve
        env:
          ARM_USE_OIDC: true
          ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
          ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
          ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
          TF_VAR_ssh_public_key: ${{ secrets.SSH_PUBLIC_KEY }}
```

> **Note:** GitHub Actions workflows always run on `ubuntu-latest` and use bash internally — this is correct and expected even though your local shell is PowerShell.

### Validation
- Open a PR with a minor change (e.g., add a tag to tfvars) — the plan posts as a PR comment
- Merge the PR — the apply job runs automatically
- Check the Actions tab for the full run logs

### Stretch Goals
- Configure a GitHub Environment with required reviewers (Settings → Environments → New environment → Required reviewers) so apply requires manual approval
- Add a `terraform-destroy` workflow triggered only by `workflow_dispatch` as a manual safety valve
- Add `tfsec` or `checkov` as a security scanning step before plan

---

## Module 8: Drift Detection, Refactoring & Day-2 Operations

**The vSphere gap:** Real Terraform work isn't just initial deploys — it's managing infrastructure that exists. This module covers the operational patterns you'll use daily in a company role.

### Concepts

**Drift** — real-world infrastructure changes that Terraform doesn't know about. Can happen from manual portal changes, other automation, or Azure's own updates.

**`terraform import`** — bring existing resources under Terraform management. The modern alternative is `import` blocks (Terraform 1.5+).

**`moved` blocks** — safely refactor resource addresses without destroying/recreating.

**`terraform taint` / `replace`** — force a specific resource to be destroyed and recreated.

### Exercise 8A: Detect and Resolve Drift

Simulate drift — go to the Azure portal and manually add a tag to your resource group. Then:

```powershell
# Run a plan — you should see the tag as a change to be reversed
terraform plan
# This is drift — Terraform will revert the manual change on next apply
```

Understand your options:
1. **Let Terraform revert it** — run `terraform apply`, drift is fixed
2. **Accept the drift into code** — add the tag to your `locals.tf`, run `plan` to verify it goes to zero diff
3. **Ignore it permanently** — add `ignore_changes` to the lifecycle block (use sparingly)

### Exercise 8B: Import an Existing Resource

Practice importing the state storage account you created manually in Module 1:

```hcl
# Add this import block to environments/dev/main.tf
import {
  to = azurerm_storage_account.state_backend
  id = "/subscriptions/<sub-id>/resourceGroups/rg-terraform-state/providers/Microsoft.Storage/storageAccounts/sttfstate6a9b3db0"
}

resource "azurerm_storage_account" "state_backend" {
  name                     = "sttfstate6a9b3db0"
  resource_group_name      = "rg-terraform-state"
  location                 = "eastus"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
}
```

```powershell
terraform plan    # Shows import, no changes (if config matches reality)
terraform apply   # Imports the resource into state
terraform state show azurerm_storage_account.state_backend
```

### Exercise 8C: Safely Rename a Resource with `moved`

Simulate renaming a resource (e.g., refactoring a module):

```hcl
# Add to your main.tf — tells Terraform the old address moved to a new one
moved {
  from = azurerm_resource_group.main
  to   = azurerm_resource_group.primary
}

# Then rename the resource block accordingly
resource "azurerm_resource_group" "primary" {
  # same config as before
}
```

```powershell
terraform plan    # Should show "moving" with no destroy/create
terraform apply   # Updates state only, no Azure API changes
```

### Exercise 8D: Targeted Operations

```powershell
# Plan or apply only specific resources
# Use carefully — can cause dependency issues if you're not thorough
terraform plan -target=module.networking
terraform apply -target=azurerm_resource_group.primary

# Force recreation of a specific resource (e.g., VM is in bad state)
terraform apply -replace=module.app_vm.azurerm_linux_virtual_machine.this

# Preview a full destroy before actually destroying
terraform plan -destroy

# Destroy only specific resources (reverse order matters)
terraform destroy -target=module.app_vm
```

### Exercise 8E: Scheduled Drift Detection

Create `.github/workflows/drift-detection.yml`:

```yaml
name: Drift Detection

on:
  schedule:
    - cron: '0 8 * * 1-5'  # 8am weekdays
  workflow_dispatch:

jobs:
  drift-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Azure Login
        uses: azure/login@v1
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - uses: hashicorp/setup-terraform@v3

      - name: Init
        working-directory: environments/dev
        run: terraform init
        env:
          ARM_USE_OIDC: true
          ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
          ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
          ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Check for Drift
        working-directory: environments/dev
        run: |
          terraform plan -detailed-exitcode -no-color
          if [ $? -eq 2 ]; then
            echo "::warning::Drift detected in dev environment!"
            exit 1
          fi
        env:
          ARM_USE_OIDC: true
          ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
          ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
          ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
          TF_VAR_ssh_public_key: ${{ secrets.SSH_PUBLIC_KEY }}
```

### Validation
- `terraform plan` after a manual portal change shows drift
- `moved` block refactor results in zero diff (no destroy/create)
- Import successfully brings an unmanaged resource under state control
- Drift detection workflow fails the run when drift is detected

---

## Reference: Company-Patterns Cheat Sheet

### Code Organization
| Pattern | Use When |
|---|---|
| Module per service | Reusable across environments |
| Directory per environment | Different state, different scale |
| `tfvars` files | Per-environment variable overrides |
| `TF_VAR_` env vars | Secrets, CI/CD injected values |

### State Management
| Rule | Reason |
|---|---|
| Remote backend always | Team collaboration, no local state |
| Separate state per environment | Blast radius isolation |
| State locking enabled | Prevent concurrent apply |
| State encryption at rest | Sensitive values in state |

### Security
| Rule | Reason |
|---|---|
| No secrets in code | Git is forever |
| No secrets in tfvars files | They get committed |
| Managed Identity over SP where possible | No credential rotation |
| OIDC for CI/CD | No long-lived secrets in pipelines |
| Least-privilege SP roles | Limit blast radius |

### CI/CD
| Pattern | Reason |
|---|---|
| Plan on PR | Visibility before change |
| Apply on merge | Gated execution |
| Environment protection rules | Human approval for prod |
| Concurrency groups | No parallel applies |
| Drift detection schedule | Catch out-of-band changes |

### PowerShell Quick Reference
| Bash equivalent | PowerShell |
|---|---|
| `export VAR="value"` | `$env:VAR = "value"` |
| `echo $VAR` | `Write-Host $VAR` or `echo $VAR` |
| `VAR=$(command)` | `$VAR = command` |
| `command \` (line continuation) | `` command ` `` |
| `mkdir -p path/to/dir` | `New-Item -ItemType Directory -Force -Path "path/to/dir"` |
| `cat file` | `Get-Content file` |
| `curl https://...` | `(Invoke-WebRequest -Uri "https://...").Content` |

---

## Cost Management

**Always destroy homelab resources when not in use:**

```powershell
# Destroy in reverse order of creation
cd environments/dev
terraform destroy -target=module.app_vm         # VMs cost money while running
terraform destroy -target=module.keyvault
# Keep networking — it's nearly free

# Or destroy everything at once
terraform destroy
```

**Azure Free Tier Services (always free):**
- Azure Blob Storage (first 5GB)
- Azure Key Vault (first 10,000 operations/month)
- Azure Virtual Network, NSG, Subnets — free

**Things that cost money:**
- Virtual Machines (even Standard_B1s ~$8/month if always on)
- Public IPs (~$3/month)
- Managed Disks (Standard_LRS is cheap but not free)

---

## What to Learn Next

After completing all 8 modules, these are the natural next steps for enterprise readiness:

**Testing** — `terratest` (Go-based) or `terraform test` (native, added in 1.6) for unit and integration testing modules.

**Policy as Code** — Azure Policy + Sentinel (if using Terraform Cloud) or Open Policy Agent to enforce guardrails.

**Terraform Cloud / HCP Terraform** — managed runs, state, and team access. Free tier is generous for individuals.

**Module Registry** — publishing modules internally (Azure DevOps Artifacts or GitHub Packages) so teams can version-pin shared modules.

**Azure Landing Zone** — Microsoft's enterprise-scale Terraform reference architecture. Good to study even if you don't implement it wholesale.
