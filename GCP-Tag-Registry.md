# GCP Tag Registry

This registry documents all managed tag keys and their values.
Platform tags must be registered here before use.
Workload (`wl-`) tags are self-service and do not require registration.

Last updated: 2026-04-11
Maintained by: Platform Team

---

## Current State — FAST-Deployed Tags

These are the tag keys deployed by FAST Stage 0 at the org level.
All are managed by the platform team via `iac-org-rw`.

---

### `context`

Controls which FAST stage service account can manage a resource.
Used in IAM conditions to scope automation SA permissions to their
designated part of the hierarchy.

| Value | Description | Used in IAM condition |
|-------|-------------|----------------------|
| `project-factory` | Resource managed by project factory stage | `roles/orgpolicy.policyAdmin` scoped to `iac-pf-rw` |

Future state key name: `plt-context`

---

### `environment`

Separates workloads by environment. Stage SAs (`iac-networking-rw`,
`iac-security-rw`, `iac-pf-rw`) are granted `tagUser` on each value,
allowing them to bind the tag to resources they manage.

| Value | Description | tagUser | tagViewer |
|-------|-------------|---------|-----------|
| `development` | Development workloads | `iac-networking-rw`, `iac-security-rw`, `iac-pf-rw` | `iac-networking-ro`, `iac-security-ro`, `iac-pf-ro` |
| `production` | Production workloads | `iac-networking-rw`, `iac-security-rw`, `iac-pf-rw` | `iac-networking-ro`, `iac-security-ro`, `iac-pf-ro` |

Future state key name: `plt-environment`

---

### `org-policies`

Used to control org policy exception conditions. Tags are bound to
specific resources to allow policy overrides without disabling the
policy org-wide.

| Value | Description |
|-------|-------------|
| `allowed-essential-contacts-domains-all` | Allow all domains in essential contacts org policy |
| `allowed-policy-member-domains-all` | Allow all domains in domain restricted sharing org policy |
| `allowed-sa-impersonation` | Allow service account impersonation for tagged principals |

Future state key name: `plt-org-policies`

---

## Future State — Three-Tier Prefixed Model

The current FAST tags have no prefix, which creates ambiguity at scale
as more teams and workloads are onboarded. The recommended future state
adopts a prefix-based governance model to make ownership and scope explicit.

See `GCP-Tag-Governance-Three-Tier.md` for the full governance model.

### Planned Platform Tags (`plt-`)

| Future key | Current key | Status |
|------------|-------------|--------|
| `plt-context` | `context` | Planned migration |
| `plt-environment` | `environment` | Planned migration |
| `plt-org-policies` | `org-policies` | Planned migration |
| `plt-data-classification` | — | New, not yet deployed |

### Planned Network Tags (`net-`)

| Key | Values | Status |
|-----|--------|--------|
| `net-connectivity` | `shared-vpc`, `standalone`, `peered` | Planned |
| `net-vpc-type` | `host`, `service`, `standalone` | Planned |

### Workload Tags (`wl-`)

Self-service. Workload teams manage their own keys and values within
their folder scope. Naming convention: `wl-<team>-<attribute>`.

No registration required.

---

## Querying Tags via CLI

List all org-level tag keys:
```bash
gcloud resource-manager tags keys list --parent=organizations/1041701195417
```

List values for a specific key:
```bash
gcloud resource-manager tags values list --parent=1041701195417/context
```

List tag bindings on a resource:
```bash
gcloud resource-manager tags bindings list \
  --parent=//cloudresourcemanager.googleapis.com/folders/FOLDER_ID
```
