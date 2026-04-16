# Organization Governance & Architecture

This document describes the architectural alignment, compliance boundaries, and policy exceptions for this FAST deployment.

---

## 1. FAST vs. Stellar Engine Alignment

This deployment uses a "Hardened" dataset aligned with Stellar Engine's Assured Workloads FedRAMP High deployment pattern.

### Key Architectural Choices
- **Unified Factory:** Everything is defined in YAML datasets instead of separate Terraform stages.
- **Root Level Sinks:** Aggregated logging sinks are defined at the Org level but filtered for specific folders.
- **Resource Naming:** Follows the FAST standard with specific overrides for FedRAMP compliance.
- **State Handoff:** Uses automated `.auto.tfvars` generation for cross-stage communication.

---

## 2. Assured Workloads (FedRAMP High) Constraints

When using the `FEDRAMP_HIGH` compliance regime, the following constraints are auto-enforced at the folder level:

| Category | Constraint | Impact |
|---|---|---|
| **Location** | `gcp.resourceLocations` | US-only regions. |
| **Services** | `gcp.restrictServiceUsage` | Only FedRAMP High authorized services. |
| **Encryption** | `gcp.restrictNonCmekServices` | Requires CMEK for all at-rest data. |
| **IAM** | `iam.disableServiceAccountKeyCreation` | No user-managed SA keys. |
| **Compute** | `compute.requireShieldedVm` | Shielded VMs only. |

---

## 3. Approved Policy Exceptions

### BigQuery Usage in Core Projects
**Status:** Approved Exception.
**Reason:** The default Assured Workloads service list is overly conservative and excludes BigQuery. BigQuery is required for:
- **iac-0:** Terraform provider internal lookups.
- **billing-0:** Billing export dataset for organization-wide visibility.

**Implementation:**
The `gcp.restrictServiceUsage` policy is set to `allow: all` at the project level for `iac-0` and `billing-0` to bypass the restrictive folder policy.
