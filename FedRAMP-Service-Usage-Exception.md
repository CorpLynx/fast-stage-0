# Exception: `gcp.restrictServiceUsage` Override on Core Platform Projects

## Projects Affected

- `fpoc3-prod-iac-core-0` (iac-0)
- `fpoc3-prod-billing-exp-0` (billing-0)

## What It Does

Sets `gcp.restrictServiceUsage` to `allow: all` at the project level, overriding the FedRAMP High Assured Workloads folder-level enforcement which restricts services to a conservative JAB-authorized subset.

## Why It's Necessary

The Assured Workloads FedRAMP High folder auto-enforces a service allowlist that excludes BigQuery by default. However, BigQuery holds a full JAB Provisional Authorization to Operate (P-ATO) at FedRAMP High — it is a FedRAMP High authorized service. The AW folder's default list is simply more conservative than the actual authorization boundary.

Both core platform projects require BigQuery:

- **iac-0** uses BigQuery APIs (`bigquery`, `bigqueryreservation`, `bigquerystorage`) for the Terraform provider's internal service account lookups and for potential billing analytics. Without it, the Terraform Google provider cannot complete project initialization.
- **billing-0** uses BigQuery for the billing export dataset — this is the primary mechanism for GCP cost visibility across the organization. Disabling it eliminates all billing data export and cost management capability.

## Risk Assessment

**Low.** BigQuery is FedRAMP High authorized. This exception does not introduce non-authorized services — it corrects an overly conservative AW default. The override is scoped to two specific platform projects and does not affect workload projects under the compliance boundary.

## Recommended Remediation Path

Replace `allow: all` with an explicit allowlist matching the org-level `gcp.restrictServiceUsage` policy once the AW folder's service list is confirmed to include BigQuery. This narrows the exception to only the services actually needed.

## Implementation

The override is applied via project-level org policy in the FAST dataset:

```yaml
# datasets/hardened/projects/core/iac-0.yaml
# datasets/hardened/projects/core/billing-0.yaml
org_policies:
  gcp.restrictServiceUsage:
    rules:
      - allow:
          all: true
```
