# Feature Spec: Custom Organization Policy Constraints

## Goal
Enable the creation of custom organization policy constraints (v4) using the FAST YAML factory. This allows for fine-grained resource controls that are not available in standard Google Cloud constraints.

## Stellar Engine Pattern
SE uses a dedicated `data/custom-constraint-policies/` folder and passes it to the `org_policy_custom_constraints` argument in the organization module.

## Implementation Path

### 1. Verification
Your modern FAST engine **already supports this**. The `organization-iam` module call in `organization.tf` includes:
```hcl
factories_config = {
  org_policy_custom_constraints = "${local.paths.organization}/custom-constraints"
  ...
}
```

### 2. Usage
To add a new custom constraint (e.g., "Ensure all GCS buckets have versioning enabled"):
1. Create a new YAML file in `datasets/hardened/organization/custom-constraints/`.
2. Use the following format:
```yaml
# datasets/hardened/organization/custom-constraints/custom.storageRequireVersioning.yaml
name: organizations/1041701195417/customConstraints/custom.storageRequireVersioning
resourceTypes:
- storage.googleapis.com/Bucket
methodTypes:
- CREATE
- UPDATE
condition: "resource.versioning.enabled == true"
actionType: ALLOW
displayName: Require Bucket Versioning
description: All GCS buckets must have versioning enabled at creation.
```

## Benefits
- **Automated Compliance:** Block non-compliant resource creation at the API level.
- **Data-Driven:** No Terraform code changes required to add new organization-wide rules.
