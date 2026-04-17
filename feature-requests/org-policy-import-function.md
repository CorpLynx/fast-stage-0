# Feature Spec: Org Policy Automated Imports (Secure-by-Default)

## Goal
Port the Stellar Engine logic for automatically importing organization policies that Google Cloud enables by default in new organizations (since February 2024). This prevents Terraform from trying to "un-enforce" or overwrite these baseline security settings.

## Stellar Engine Pattern
SE uses a dynamic `import` block in `organization.tf` that iterates over a known list of "secure-by-default" constraints.

## Implementation Path

### 1. Update `imports.tf`
Port the specific list of constraints from SE into your root `imports.tf` file. 

```hcl
# Add to imports.tf
import {
  for_each = toset([
    "iam.managed.disableServiceAccountKeyCreation",
    "iam.managed.disableServiceAccountKeyUpload",
    "iam.managed.preventPrivilegedBasicRolesForDefaultServiceAccounts",
    "iam.allowedPolicyMemberDomains",
    "essentialcontacts.managed.allowedContactDomains",
    "storage.uniformBucketLevelAccess",
    "compute.managed.restrictProtocolForwardingCreationForTypes"
  ])
  id = "organizations/${local.organization_id}/policies/${each.key}"
  to = module.organization-iam[0].google_org_policy_policy.default[each.key]
}
```

### 2. Synchronization
Ensure these policies are also defined in your `datasets/hardened/organization/org-policies/` folder. If they are missing, Terraform will import them and then immediately try to delete them because they aren't in the YAML.

## Benefits
- **Zero Friction:** Prevents `403` or `409` errors when Terraform tries to manage a policy Google has already locked down.
- **Accuracy:** Ensures your local Terraform state perfectly reflects the actual organizational reality from Day 1.
- **Security:** Maintains Google's recommended baseline without manual intervention.
