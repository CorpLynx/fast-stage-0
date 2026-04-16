# GCP Tag Governance & Registry

This document describes the tagging strategy for the organization, including the three-tier governance model and the registry of active tags.

---

## 1. Three-Tier Governance Model

Tags are divided into three tiers based on ownership and scope, enforced through IAM.

| Tier | Prefix | Owner | Scope | Purpose |
|---|---|---|---|---|
| **Platform** | `plt-` | Platform Team | Organization | Enterprise taxonomy (environment, classification). |
| **Network** | `net-` | Network Team | Network Folder | Connectivity and VPC attributes. |
| **Workload** | `wl-` | App Teams | Workload Folder | Team-specific metadata (cost-center, owner). |

---

## 2. Tag Registry (Current State)

These tags are deployed by FAST Stage 0 and are used to scope automation permissions.

### `context`
Scopes service account permissions to specific parts of the hierarchy.
- **Value:** `project-factory` (Used by `iac-pf-rw`)

### `environment`
Separates development and production workloads.
- **Values:** `development`, `production`

### `org-policies`
Controls organization policy exception conditions.
- **Value:** `allowed-essential-contacts-domains-all`
- **Value:** `allowed-policy-member-domains-all`
- **Value:** `allowed-sa-impersonation`

---

## 3. Implementation Details

### Tag Inheritance
Tags bound to a folder are automatically inherited by all sub-folders and projects. This allows for centralized IAM conditions without tagging every individual resource.

### IAM Conditions
Tags are used in IAM conditions to grant "Scoped" permissions. Example:
```bash
--condition="expression=resource.matchTag('ORG_ID/environment', 'production')"
```

### CLI Querying
```bash
# List org-level keys
gcloud resource-manager tags keys list --parent=organizations/[ORG_ID]

# List values for a key
gcloud resource-manager tags values list --parent=[ORG_ID]/[KEY]
```
