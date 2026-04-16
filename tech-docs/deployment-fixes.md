# FAST Stage 0: Deployment Fixes Summary

This document summarizes the authentication, policy, and API issues encountered during the initial local deployment of FAST Stage 0 (Organization Setup) and how they were resolved.

## 1. Authentication & Quota Errors (`403 Forbidden`)

### Symptoms
Terraform failed to read or create organization-level resources (SCC modules, Essential Contacts, etc.) with errors mentioning:
- `Your application is authenticating by using local Application Default Credentials.`
- `The [API] requires a quota project, which is not set by default.`
- Errors referencing project `764086051850` (the internal GCloud CLI project).

### Root Cause
When using local user credentials (ADC) for Organization-level operations, Google Cloud requires an explicit project to track API quota usage. By default, the Google Terraform provider may fail to pass the quota project configured in the CLI, causing the API to default to the internal CLI project which the user does not have permission to use.

### Resolution
A `providers.tf` file was created in the root directory to explicitly configure the provider to use the bootstrap project for quota:

```hcl
provider "google" {
  user_project_override = true
  billing_project       = "fpoc-seed-bootstrap"
}

provider "google-beta" {
  user_project_override = true
  billing_project       = "fpoc-seed-bootstrap"
}
```

## 2. Service Usage Restriction (`403 Disallowed by Policy`)

### Symptoms
Terraform plans failed with:
`Error 403: Request is disallowed by organization's constraints/gcp.restrictServiceUsage constraint ... attempting to use service 'bigquery.googleapis.com'.`

### Root Cause
An active Organization Policy (`constraints/gcp.restrictServiceUsage`) on the "FedRAMP High" folder acted as an allowlist for APIs. `bigquery.googleapis.com` was missing from this list, preventing Terraform from interacting with BigQuery even if the API was technically enabled in the project.

### Resolution
The `bigquery.googleapis.com` service was manually added to the allowed values for the `constraints/gcp.restrictServiceUsage` policy on the affected folder.

## 3. Concurrent Update Conflicts (`409 Operation Aborted`)

### Symptoms
During `terraform apply`, several Organization Policies failed to create with:
`Error 409: The operation was aborted.`

### Root Cause
The Google Cloud Organization Policy API has strict concurrency limits for updates at the organization level. Attempting to provision a large number of policies (~60) simultaneously often triggers rate-limiting aborts.

### Resolution
The deployment was completed using an **Iterative Apply Strategy**. Since Terraform is idempotent, running `apply` multiple times allowed the process to pick up where it left off, eventually provisioning 100% of the resources over four attempts.
