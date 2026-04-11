# Runbook: Migrate Stage-0 State from TFE to GCS

## Prerequisites

- `terraform` CLI installed
- `gcloud` CLI authenticated with access to the outputs bucket
- Access to the TFE workspace (for state pull)
- The outputs bucket name (check TFE outputs or `defaults.yaml` for `output_files.storage_bucket`)

## Steps

### 1. Pull state from TFE

```bash
cd fast-stage-0
terraform login
terraform state pull > terraform.tfstate
```

Verify the file is valid:
```bash
cat terraform.tfstate | python3 -m json.tool > /dev/null && echo "Valid JSON"
```

### 2. Copy the provider file from GCS

Stage-0 generated a provider file for itself that includes the `backend "gcs"` block:

```bash
gcloud storage cp gs://<OUTPUTS_BUCKET>/providers/0-org-setup-providers.tf ./
```

Replace `<OUTPUTS_BUCKET>` with your actual bucket name (e.g. `fpoc2-prod-iac-core-0-iac-outputs`).

### 3. Remove any existing cloud/backend config

If you have a `cloud {}` or `backend` block anywhere in your `.tf` files (outside the provider file you just copied), remove it. The provider file is now the sole source of backend config.

### 4. Migrate state to GCS

```bash
terraform init -migrate-state
```

Terraform will prompt:

```
Do you want to copy existing state to the new backend?
```

Type `yes`. State moves from TFE to the GCS bucket.

### 5. Verify

```bash
terraform state list
```

Should show all your resources. Run a plan to confirm no drift:

```bash
terraform plan
```

Expected: no changes (or only expected changes from any pending config updates).

### 6. Clean up

- Delete or archive the TFE workspace for stage-0 (optional)
- Delete the local `terraform.tfstate` file — state is now in GCS
- Commit the provider file to the repo

```bash
rm terraform.tfstate
rm terraform.tfstate.backup  # if exists
```

## What changed

| Before | After |
|---|---|
| State in TFE | State in GCS bucket |
| Auth via `GOOGLE_CREDENTIALS` env var in TFE | Auth via `impersonate_service_account` in provider file |
| Runs triggered by TFE | Runs triggered by GHA (after WIF setup) |

## Next steps

- Set up Workload Identity Federation for GHA authentication
- Create `cicd-workflows.yaml` in `datasets/hardened/` to generate the GHA workflow
- Re-apply stage-0 to generate the workflow file in the outputs bucket
- Copy the workflow to `.github/workflows/` in this repo
