# FAST vs Stellar Engine AW Alignment

## Overview

This document describes the changes made to align the FAST hardened dataset with
Stellar Engine's Assured Workloads FedRAMP High deployment pattern, based on analysis
of `stellar-engine-main-2/fast/stages-aw/0-bootstrap/`.

---

## Changes Made

### 1. Removed org-level `gcp.restrictServiceUsage` policy

**File:** `datasets/hardened/organization/org-policies/serviceusage.yaml`

**What changed:** The `gcp.restrictServiceUsage` org policy is now commented out entirely.

**Why:** Stellar Engine does not set this policy at the org level. Service usage
restrictions are enforced by the Assured Workloads FedRAMP High folder's
auto-enforcement. Setting this at the org level creates a double-restriction that
blocks FedRAMP-authorized services like BigQuery from being used in projects under
the AW folder — even though BigQuery holds a JAB P-ATO at FedRAMP High.

**Impact:** Service restrictions are now governed solely by the AW folder's
auto-enforced allowlist, which is the correct boundary for FedRAMP High compliance.

---

### 2. Removed project-level `gcp.restrictServiceUsage` overrides

**Files:** `datasets/hardened/projects/core/iac-0.yaml`, `datasets/hardened/projects/core/billing-0.yaml`

**What changed:** The `gcp.restrictServiceUsage: allow: all` project-level overrides
were removed from iac-0 and billing-0.

**Why:** These were added as a workaround for the org-level policy conflict described
above. With the org-level policy commented out, the project-level overrides are no
longer needed.

---

## Key Architectural Differences vs Stellar Engine

### Folder structure

Stellar Engine creates a **Common Services folder** directly under the AW workload
folder and places all core projects (automation, billing, logging) inside it:

```
AW Workload Folder (FEDRAMP_HIGH)
└── Common Services/        ← branch-common-services-folder
    ├── iac-core-0          ← automation project
    ├── billing-exp-0       ← billing project
    └── audit-logs-0        ← logging project
```

FAST (this repo) places core projects directly under the AW workload folder:

```
awroot/                     ← plain parent folder (required by AW API)
└── frhigh/                 ← AW workload folder (FEDRAMP_HIGH)
    ├── fpoc3-prod-iac-core-0
    ├── fpoc3-prod-billing-exp-0
    ├── fpoc3-prod-audit-logs-0
    ├── networking/
    ├── security/
    ├── workloads/
    └── data-platform/
```

Both approaches place core projects inside the AW boundary. The Common Services
sub-folder pattern is a cleaner organizational separation but functionally equivalent.

### AW Workload resource

Stellar Engine sets `provisioned_resources_parent = ""` (empty string) on the
`google_assured_workloads_workload` resource. FAST's folder module sets it to `null`
when no parent folder is specified, which caused API validation errors. The FAST
module was updated to use `awroot` as the parent folder, which provides a valid
`folders/folder_id` value for `provisioned_resources_parent`.

### Org policies

Stellar Engine's org policy approach is more minimal — they rely on AW auto-enforcement
for service restrictions and only set policies that are explicitly required. FAST's
hardened dataset has a more comprehensive set of org policies which is appropriate for
the hardened security posture, but `gcp.restrictServiceUsage` specifically conflicts
with AW auto-enforcement and should not be set at the org level.

### Project services

Stellar Engine's core projects have minimal service lists. FAST's core projects have
more comprehensive service lists which is appropriate for the full FAST feature set
(WIF, KMS, observability, etc.).

---

## Remaining Differences (Intentional)

- FAST has 89 custom org policy constraints vs Stellar Engine's smaller set — this is
  intentional for the hardened security posture
- FAST uses CMEK for all storage vs Stellar Engine's optional CMEK — intentional
- FAST has more comprehensive IAM bindings and service accounts — intentional for
  multi-stage FAST deployment
