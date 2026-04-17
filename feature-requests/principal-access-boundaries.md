# Feature Spec: Principal Access Boundaries (PABs)

## Goal
Implement support for Principal Access Boundaries (PABs) in the FAST YAML factory. PABs provide a layer of protection that limits the resources a principal can access, even if they have the necessary IAM roles. This is a critical security control for multi-tenant environments and hardening service accounts.

## Stellar Engine Pattern
SE uses a dedicated `data/organization/pab-policies/` folder for PAB definitions and passes it to the `pab_policies` argument in the organization module. PABs are managed alongside Custom Roles and Org Policies as part of the organization's security baseline.

## Implementation Path

### 1. Update the `organization` Module
The underlying `organization` module needs to be extended to support PAB resources.

**File: `modules/organization/variables.tf`**
Add a new variable to accept PAB configurations from the factory:
```hcl
variable "pab_policies" {
  description = "Principal Access Boundary policies, in {ID => {display_name, rules = []}} format."
  type = map(object({
    display_name = string
    rules = list(object({
      description = string
      effect      = string
      resources   = list(string)
    }))
  }))
  default  = {}
  nullable = false
}
```

**File: `modules/organization/pab.tf` (New File)**
Implement the PAB resource:
```hcl
resource "google_iam_principal_access_boundary_policy" "pab_policies" {
  for_each     = var.pab_policies
  organization = local.organization_id_numeric
  location     = "global"
  display_name = each.value.display_name
  policy_id    = each.key
  
  dynamic "rules" {
    for_each = each.value.rules
    content {
      description = rules.value.description
      effect      = rules.value.effect
      resources   = rules.value.resources
    }
  }
}
```

### 2. Update the YAML Factory in Stage 0
Stage 0 (`0-org-setup`) must be updated to load PAB policies from the dataset.

**File: `locals.tf` (or `organization.tf`)**
```hcl
locals {
  # ... other loaders
  pab_policies = {
    for f in try(fileset("${local.paths.organization}/pab-policies", "*.yaml"), []) :
    replace(f, ".yaml", "") => yamldecode(file("${local.paths.organization}/pab-policies/${f}"))
  }
}
```

### 3. Usage Example
To restrict a service account's blast radius to specific folders:
1. Create `datasets/hardened/organization/pab-policies/restrict-resman.yaml`:
```yaml
display_name: "Restrict Resman to Production"
rules:
  - description: "Allow access only to production hierarchy"
    effect: ALLOW
    resources:
      - "folders/1234567890" # Production Folder
```

## Benefits
- **Defense in Depth:** Even if a principal's credentials are leaked, PABs ensure they cannot be used to access resources outside the boundary.
- **Data-Driven Guardrails:** Security teams can define boundaries in YAML without modifying core Terraform code.
- **Compliance:** Helps satisfy NIST 800-53 (AC-3) and FedRAMP requirements for logical access restrictions.
