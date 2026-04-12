# Assured Workloads — FedRAMP High: Auto-Enforced Org Policy Constraints

When you create an Assured Workloads folder with `compliance_regime: FEDRAMP_HIGH`, Google Cloud automatically applies the following organization policy constraints at the folder level. All child folders and projects inherit these policies.

## Google Cloud-Wide Organization Policy Constraints

| Constraint | Value | Description |
|---|---|---|
| `gcp.resourceLocations` | `in:us-locations` | Restricts resource creation to US-only regions. Prevents resources from being created in non-US regions, multi-regions, or locations. |
| `gcp.restrictServiceUsage` | FedRAMP High authorized services only | Limits which GCP services can be enabled to those holding FedRAMP High authorization. Unsupported services are blocked at runtime. |
| `gcp.restrictNonCmekServices` | All in-scope API service names | Requires Customer-Managed Encryption Keys (CMEK) for at-rest data. Services listed must use CMEK rather than Google-managed default encryption. |
| `gcp.restrictTLSVersion` | Deny: `TLS_1_0`, `TLS_1_1` | Blocks deprecated TLS versions. Only TLS 1.2+ is permitted. |

## IAM Constraints

| Constraint | Value | Description |
|---|---|---|
| `iam.disableServiceAccountKeyCreation` | `enforce: true` | Prevents creation of user-managed service account keys. |
| `iam.disableServiceAccountKeyUpload` | `enforce: true` | Prevents uploading user-managed service account keys. |

## Compute Constraints

| Constraint | Value | Description |
|---|---|---|
| `compute.requireShieldedVm` | `enforce: true` | Requires all new VM instances to use Shielded VM features (Secure Boot, vTPM, Integrity Monitoring). |
| `compute.requireOsLogin` | `enforce: true` | Requires OS Login for SSH access to VM instances, enforcing IAM-based access control. |

## Storage Constraints

| Constraint | Value | Description |
|---|---|---|
| `storage.uniformBucketLevelAccess` | `enforce: true` | Requires uniform bucket-level access on all Cloud Storage buckets, disabling per-object ACLs. |

## Additional Controls (Non-Org-Policy)

Beyond org policy constraints, Assured Workloads for FedRAMP High also enforces:

- **Data residency**: All data at rest is restricted to US locations.
- **Personnel access controls**: First-level and second-level Google support personnel must be US-based and have completed enhanced background checks.
- **Encryption**: FIPS 140-2 compliant key management. Cloud HSM keys are available for FIPS 140-2 Level 3.
- **Compliance monitoring**: Violation notifications and the Assured Workloads monitoring dashboard track compliance drift.
- **Service restriction**: Only FedRAMP High authorized GCP services can be used within the boundary.

## Sources

- [Google Cloud Assured Workloads Overview](https://docs.cloud.google.com/assured-workloads/docs/overview)
- [Google Cloud FedRAMP Implementation Guide](https://docs.cloud.google.com/architecture/fedramp-implementation-guide)
- [Assured Workloads Control Packages](https://docs.cloud.google.com/assured-workloads/docs/control-packages)
- [Restrict Resource Usage for Workloads](https://cloud.google.com/assured-workloads/docs/restrict-resource-usage)
- [FedRAMP and DoD Compliance Scope](https://docs.cloud.google.com/architecture/security/fedramp-dod-compliance-scope)

> Content was rephrased for compliance with licensing restrictions. Refer to the official Google Cloud documentation for authoritative details.
