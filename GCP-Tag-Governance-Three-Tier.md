# GCP Tag Governance — Three-Tier Model

## Overview

This document describes a prefix-based tag governance model for enterprise GCP
organizations. Tags are divided into three tiers based on ownership and scope,
enforced through IAM role assignments rather than native GCP constraints.

The prefix convention is a documented standard. The IAM structure is what makes
it structurally difficult to violate.

---

## The Three Tiers

### Tier 1 — Platform Tags (`plt-`)

| Attribute | Value |
|-----------|-------|
| Prefix | `plt-` |
| Defined at | Organization |
| Created by | Platform team only |
| Applied by | Platform team only |
| Examples | `plt-environment`, `plt-data-classification`, `plt-context` |

Platform tags represent enterprise-wide taxonomy owned and governed by the
platform team. They are used in IAM conditions that span the entire org hierarchy.
No other team can create or bind these tags.

**IAM enforcement:**
- `roles/resourcemanager.tagAdmin` granted to platform team SA/group at org level only
- No other principal has `tagAdmin` at the org level
- Workload and network teams have no `tagAdmin` at org scope → cannot create `plt-` keys

---

### Tier 2 — Network Tags (`net-`)

| Attribute | Value |
|-----------|-------|
| Prefix | `net-` |
| Defined at | Network folder or network project |
| Created by | Network team |
| Applied by | Network team creates; workloads can bind pre-created values |
| Examples | `net-connectivity`, `net-vpc-type`, `net-peering-group` |

Network tags are owned by the network team and scoped to the network folder or
a shared network project. They can be shared out to workload folders and projects
via tag bindings, but workloads cannot create new `net-` tag keys — only bind
values that the network team has already defined.

**IAM enforcement:**
- `roles/resourcemanager.tagAdmin` granted to network team at network folder/project scope
- Network team has no `tagAdmin` at org level → cannot create org-scoped tags
- Workload teams get `roles/resourcemanager.tagUser` on their folders → can bind existing `net-` values but cannot create new keys or values
- `roles/resourcemanager.tagAdmin` is NOT granted to workload teams at network scope → cannot create new `net-` keys

---

### Tier 3 — Workload Tags (`wl-`)

| Attribute | Value |
|-----------|-------|
| Prefix | `wl-` |
| Defined at | Workload top-level folder |
| Created by | Workload teams |
| Applied by | Workload teams |
| Examples | `wl-app`, `wl-cost-center`, `wl-owner` |

Workload tags are self-service. Teams can create and bind their own tags within
their folder scope. They cannot create tags at the org or network level, so
`wl-` tags are naturally contained within the workload hierarchy.

**IAM enforcement:**
- `roles/resourcemanager.tagAdmin` granted to workload teams at their top-level folder only
- No `tagAdmin` at org or network scope → cannot create `plt-` or `net-` keys
- Tags created here are only visible and usable within the workload folder subtree

---

## IAM Role Summary

| Role | Platform team | Network team | Workload teams |
|------|--------------|--------------|----------------|
| `tagAdmin` @ org | ✅ | ❌ | ❌ |
| `tagAdmin` @ network folder | ❌ | ✅ | ❌ |
| `tagAdmin` @ workload folder | ❌ | ❌ | ✅ |
| `tagUser` @ workload folder | ✅ | ✅ | ✅ |
| `tagViewer` @ org | ✅ | ✅ | ✅ |

---

## Limitations

GCP does not natively enforce tag key naming conventions. The prefix model is a
documented standard enforced structurally through IAM scope, not through a
technical constraint on the key name itself.

The remaining gap: a team with `tagAdmin` at their scope could technically create
a key with any name, including one that violates the prefix convention for their
tier. Recommended mitigations:

- **Terraform pipeline policy (Sentinel/OPA)** — reject plans where a tag key
  name doesn't match the expected prefix for the scope being targeted. Strongest
  control if all tag management goes through IaC.
- **Event-driven detection** — Cloud Asset Inventory + Pub/Sub to detect tag key
  creation and alert on naming violations. Reactive but catches manual console actions.
- **Documentation + access reviews** — periodic review of tag keys created in each
  scope to catch drift.
