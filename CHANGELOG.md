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
