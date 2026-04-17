# Principal Access Boundaries (PABs)

Principal Access Boundaries (PABs) provide a layer of protection that limits the resources a principal can access, even if they have the necessary IAM roles. This is a critical security control for multi-tenant environments and hardening service accounts.

---

## 1. How PABs Work

PABs act as a "deny-by-default" filter for IAM permissions. Even if a user or service account has `roles/owner` at the organization level, a PAB can restrict that access to only a specific subset of folders or projects.

- **Effect:** Access is allowed only to the resources listed in the rules (and their descendants).
- **Scope:** Applied to principals (users, groups, or service accounts) to define their "blast radius."
- **Location:** Defined at the organization level but can reference resources anywhere in the hierarchy.

---

## 2. Defining Policies (YAML Factory)

PAB policies are managed as part of the organization's security baseline. They are defined in YAML files and automatically loaded by the Stage 0 factory.

### File Location
Place your PAB policy definitions in the following directory:
`fast-stage-0/datasets/hardened/organization/pab-policies/*.yaml`

### YAML Structure
Each file should define a single PAB policy. The filename (excluding `.yaml`) will be used as the `policy_id`.

```yaml
display_name: "Short description of the boundary"
enforcement_version: "latest" # Optional, defaults to latest
rules:
  - description: "Detailed explanation of this rule"
    resources:
      - "//cloudresourcemanager.googleapis.com/folders/1234567890" # Production Folder
      - "//cloudresourcemanager.googleapis.com/projects/my-prod-project-123"
```

> **Note:** Resources must use the full resource name format (e.g., `//cloudresourcemanager.googleapis.com/folders/12345`).

---

## 3. Usage Example: Hardening Resource Manager

To restrict a service account's access so it can only manage resources within a specific "Production" folder:

1. Create `fast-stage-0/datasets/hardened/organization/pab-policies/restrict-resman.yaml`:
```yaml
display_name: "Restrict Resman to Production"
rules:
  - description: "Allow access only to the production hierarchy"
    resources:
      - "//cloudresourcemanager.googleapis.com/folders/4567890123" # Replace with your Production Folder ID
```

2. After deploying with Terraform, the policy will be available at the organization level. You can then bind this policy to a principal using IAM (this part is typically handled in `iam_bindings` or `iam_by_principals` in Stage 0 or Stage 1).

---

## 4. Implementation Details

- **Module:** The logic is implemented in the `organization` module (`pab.tf`).
- **Provider:** Uses the `google-beta` provider for PAB resources.
- **Factory:** Stage 0 automatically scans the `pab-policies` directory and passes the configurations to the module.

### Terraform Integration
The `pab_policies` argument in the `organization` module accepts the following format:
```hcl
pab_policies = {
  "my-policy-id" = {
    display_name        = "My Policy"
    enforcement_version = "latest"
    rules = [
      {
        description = "Allow access to folder X"
        resources   = ["//cloudresourcemanager.googleapis.com/folders/12345"]
      }
    ]
  }
}
```
