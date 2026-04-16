# FAST Deployment & Maintenance Runbooks

This document contains step-by-step guides for bootstrapping, maintaining, and fixing common issues in your FAST environment.

---

## 1. Initial Bootstrap Setup (Cloud Shell)

Use these steps to prepare your GCP organization before running Terraform for the first time.

### Find Your IDs
```bash
gcloud organizations list
gcloud billing accounts list
gcloud config get-value account
ORG_ID=$(gcloud organizations list --format="value(ID)" --limit=1)
gcloud organizations describe "$ORG_ID" --format="value(owner.directoryCustomerId)"
```

### Set Your Variables
```bash
export DOMAIN="gigachadglobal.org"
export ORG_ID="1041701195417"
export BILLING_ACCOUNT_ID="014F76-ED4E67-7CCCE1"
export FAST_PREFIX="fpoc"
export DEFAULT_REGION="us-east4"
export SEED_PROJECT="${FAST_PREFIX}-seed-bootstrap"
export BOOTSTRAP_SA_NAME="fast-bootstrap"
export BOOTSTRAP_SA_EMAIL="${BOOTSTRAP_SA_NAME}@${SEED_PROJECT}.iam.gserviceaccount.com"
export SA_MEMBER="serviceAccount:${BOOTSTRAP_SA_EMAIL}"
```

### Create Seed Project & Enable APIs
```bash
gcloud projects create "$SEED_PROJECT" --organization="$ORG_ID" --name="FAST Bootstrap Seed"
gcloud billing projects link "$SEED_PROJECT" --billing-account="$BILLING_ACCOUNT_ID"

gcloud services enable \
  cloudresourcemanager.googleapis.com \
  cloudbilling.googleapis.com \
  iam.googleapis.com \
  cloudidentity.googleapis.com \
  orgpolicy.googleapis.com \
  serviceusage.googleapis.com \
  storage.googleapis.com \
  essentialcontacts.googleapis.com \
  --project="$SEED_PROJECT"
```

---

## 2. Common Deployment Fixes

If you encounter errors during `terraform plan` or `apply`, refer to these known resolutions.

### Authentication & Quota Errors (403)
**Symptoms:** Errors referencing project `764086051850` or requiring a "quota project".
**Resolution:** Ensure your `providers.tf` file explicitly sets the quota project:
```hcl
provider "google" {
  user_project_override = true
  billing_project       = "fpoc-seed-bootstrap"
}
```

### Service Usage Restriction (403 Disallowed)
**Symptoms:** `Request is disallowed by constraints/gcp.restrictServiceUsage`.
**Resolution:** Manually allow the blocked service (e.g., `bigquery.googleapis.com`) on the affected folder via `gcloud`:
```bash
gcloud resource-manager org-policies allow constraints/gcp.restrictServiceUsage [SERVICE] --folder=[FOLDER_ID]
```

### Concurrent Update Conflicts (409 Aborted)
**Symptoms:** `Error 409: The operation was aborted` during Org Policy creation.
**Resolution:** Run `terraform apply` multiple times. Terraform is idempotent and will eventually complete all policies.

---

## 3. Migrate State from TFE to GCS

### Steps
1. **Pull state from TFE:**
   ```bash
   terraform state pull > terraform.tfstate
   ```
2. **Copy the provider file from GCS:**
   ```bash
   gcloud storage cp gs://<OUTPUTS_BUCKET>/providers/0-org-setup-providers.tf ./
   ```
3. **Initialize migration:**
   ```bash
   terraform init -migrate-state
   ```
4. **Cleanup:**
   ```bash
   rm terraform.tfstate
   ```
