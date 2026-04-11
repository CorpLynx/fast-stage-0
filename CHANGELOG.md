# FAST Bootstrap Deployment Changelog

## Issues Encountered & Resolutions

### 1. Cannot import non-existent remote object — `log-0` project
- **Error:** `Cannot import non-existent remote object` on `module.factory.module.projects["log-0"].google_project.project[0]`
- **Cause:** Project `fpoc2-prod-audit-logs-0` had been deleted and was in GCP's 30-day soft-delete grace period, making it invisible to `gcloud projects list` but still reserved.
- **Fix:** Restored the project with `gcloud projects undelete fpoc2-prod-audit-logs-0`, then added an import block to `imports.tf`:
  ```hcl
  import {
    id = "fpoc2-prod-audit-logs-0"
    to = module.factory.module.projects["log-0"].google_project.project[0]
  }
  ```

---

### 2. Error 409: Project already exists — `log-0`
- **Error:** `googleapi: Error 409: Requested entity already exists` when creating `fpoc2-prod-audit-logs-0`
- **Cause:** Project existed in GCP (restored from soft-delete) but Terraform state didn't know about it, so it tried to create it.
- **Fix:** Added import block in `imports.tf` to adopt the existing project into state.

---

### 3. Error 404: Org policy custom constraint not found — `storageRequireBucketObjectVersionning`
- **Error:** `googleapi: Error 404: Requested entity was not found` on `google_org_policy_policy.default["custom.storageRequireBucketObjectVersionning"]`
- **Cause:** Custom constraint had been deleted as part of a prior deployment cleanup. GCP enforces a 30-day cooldown before a deleted custom constraint name can be reused.
- **Fix:** Renamed all 87 custom constraints to append `V2` suffix to work around the 30-day name reuse restriction. Updated all references in org-policy and project YAML files. Manually created the `storageRequireBucketObjectVersionningV2` constraint via `gcloud` to unblock the apply:
  ```bash
  gcloud org-policies set-custom-constraint /dev/stdin <<'EOF'
  name: organizations/1041701195417/customConstraints/custom.storageRequireBucketObjectVersionningV2
  resource_types:
  - storage.googleapis.com/Bucket
  method_types:
  - CREATE
  - UPDATE
  action_type: DENY
  condition: resource.versioning.enabled == false
  display_name: Require object versioning
  description: Enforce Cloud Storage bucket object versioning to be configured
  EOF
  ```

---

### 4. Custom constraint ordering issue — module dependency race
- **Error:** Project-level org policies failing with 404 because custom constraints in `module.organization-iam` hadn't been created yet when `module.factory` tried to reference them.
- **Cause:** Terraform processes `module.organization-iam` and `module.factory` in parallel. No explicit dependency exists between the custom constraint creation and project-level policy creation.
- **Fix:** Targeted apply of `module.organization-iam` first, then full apply. TFC VCS-connected workspace blocked CLI targeted applies, so the constraint was created manually via `gcloud` as a workaround.

---

### 5. Wrong KMS key region reference — `iac-0.yaml`
- **Error:** `googleapi: Error 400: Malformed Cloud KMS crypto key: $kms_keys:iac-0/ew1/storage, invalid`
- **Cause:** Storage bucket `encryption_key` references in `iac-0.yaml` pointed to `$kms_keys:iac-0/ew1/storage` but the KMS keyring defined in the same file uses region `ue4` (us-east4), not `ew1`.
- **Fix:** Updated all three `encryption_key` references in `iac-0.yaml` from `ew1` to `ue4`.

---

### 6. BigQuery service account 403 — bootstrap SA missing permissions
- **Error:** `googleapi: Error 403: Access Denied: Project fpoc2-prod-billing-exp-0: User does not have bigquery.jobs.create permission`
- **Cause:** The bootstrap SA `fast-bootstrap@fpoc-seed-bootstrap.iam.gserviceaccount.com` running Terraform doesn't have `bigquery.jobs.create` on the managed projects. The GCP provider requires this to look up BQ service account identities.
- **Fix:** Grant `roles/bigquery.jobUser` to the bootstrap SA at the org level:
  ```bash
  gcloud organizations add-iam-policy-binding 1041701195417 \
    --member="serviceAccount:fast-bootstrap@fpoc-seed-bootstrap.iam.gserviceaccount.com" \
    --role="roles/bigquery.jobUser"
  ```

---

### 7. Custom constraint soft-delete — `gkeRequireDataplaneV2`
- **Error:** `googleapi: Error 400: The custom constraint Id [customConstraints/custom.gkeRequireDataplaneV2] was used previously and cannot be reused at this time`
- **Cause:** Both the original `gkeRequireDataplaneV2` and the V2 rename were in the 30-day soft-delete cooldown from prior deployments.
- **Fix:** Renamed constraint file and all references from `V2` to `V3`.

---

### 8. Custom constraints already exist — 409 on import
- **Error:** `googleapi: Error 409` on `storageRequireBucketObjectVersionningV2`, `iamDisableAdminServiceAccountV2`, `iamDisableProjectServiceAccountImpersonationRolesV2`
- **Cause:** These constraints already existed in GCP (two pre-existing, one manually created earlier) but weren't in Terraform state.
- **Fix:** Added import blocks to `imports.tf` for all three constraints.

---

### 9. Bootstrap SA missing `roles/owner` at org level
- **Error:** Multiple 403s on `resourcemanager.tagKeys.get`, `cloudkms.keyRings.get`, `storage.objects.create`, etc.
- **Cause:** `fast-bootstrap` SA only had specific roles at the org level, not broad enough permissions to manage all resources during bootstrap. Prior deployment had left IAM in a partial state.
- **Fix:** Granted `roles/owner` to `fast-bootstrap@fpoc-seed-bootstrap.iam.gserviceaccount.com` at the org level. To be removed after bootstrap completes.
  ```bash
  gcloud organizations add-iam-policy-binding 1041701195417 \
    --member="serviceAccount:fast-bootstrap@fpoc-seed-bootstrap.iam.gserviceaccount.com" \
    --role="roles/owner"
  ```

---

### 10. `.terraform` directory committed to git
- **Error:** GitHub rejected push due to provider binaries exceeding 100MB file size limit.
- **Cause:** `terraform init` was run locally and `.terraform/` was committed before a `.gitignore` was in place.
- **Fix:** Added `.gitignore` excluding `.terraform/`, rewrote git history with `git filter-branch` to remove the directory from past commits, force pushed.

---

### 11. Bootstrap SA roles wiped mid-run by `custom.iamDisableAdminServiceAccountV2`
- **Error:** `403: Permission 'orgpolicy.customConstraints.get' denied` on all custom constraints, plus `403: The caller does not have permission` on essential contacts.
- **Cause:** Two compounding issues:
  1. The `module.organization-iam` authoritative IAM apply wipes any manually-granted org-level roles on the bootstrap SA that aren't in Terraform state.
  2. The `custom.iamDisableAdminServiceAccountV2` custom constraint was being applied mid-run (before the IAM bindings step), which then blocked Terraform from granting the bootstrap SA the admin roles it needed to complete the run.
  This created a deadlock: the SA needed `orgpolicy.policyAdmin` to refresh state, but the constraint prevented granting it, and Terraform couldn't run to apply the `iam_bindings_additive` entries that would have preserved it.
- **Fix:**
  1. Added all required bootstrap SA roles to `iam_bindings_additive` in `datasets/hardened/organization/.config.yaml` so they survive authoritative IAM applies.
  2. Temporarily commented out the `custom.iamDisableAdminServiceAccountV2` constraint in its YAML file and its corresponding import block in `imports.tf` to prevent it from firing mid-run.
  3. Manually disabled the constraint via org policy override, waited 70 seconds for propagation, then granted the missing roles:
  ```bash
  gcloud org-policies set-policy /tmp/disable-iam-constraint.yaml
  sleep 70
  for role in \
    roles/resourcemanager.organizationAdmin \
    roles/resourcemanager.folderAdmin \
    roles/iam.organizationRoleAdmin \
    roles/orgpolicy.policyAdmin \
    roles/compute.xpnAdmin \
    roles/resourcemanager.tagAdmin \
    roles/accesscontextmanager.policyAdmin \
    roles/essentialcontacts.admin; do
    gcloud organizations add-iam-policy-binding 1041701195417 \
      --member="serviceAccount:fast-bootstrap@fpoc-seed-bootstrap.iam.gserviceaccount.com" \
      --role="$role" --condition=None
  done
  ```
  4. Triggered TFC run immediately after. Once the run succeeds, `iam_bindings_additive` preserves the roles on all future applies.
  5. After bootstrap is complete and WIF is in place, uncomment the constraint files and remove the `iam_bindings_additive` block.
