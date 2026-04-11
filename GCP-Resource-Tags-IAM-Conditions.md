# GCP Resource Tags & IAM Conditions

## What are Resource Tags?

GCP resource tags are key-value pairs attached to resources (orgs, folders, projects)
used to control IAM access via conditions. Unlike labels (which are just metadata),
tags are enforced by IAM and can gate who can do what.

A tag has three components:

- `TagKey` — the key name (e.g. `environment`, `workload`)
- `TagValue` — a valid value for that key (e.g. `production`, `data-platform`)
- `TagBinding` — attaching a key/value pair to a specific resource

---

## Tag Scoping

Tag keys are defined at a specific level in the resource hierarchy:

| Scope | Parent | Reference in condition |
|-------|--------|----------------------|
| Organization | `organizations/ORG_ID` | `ORG_ID/key` |
| Folder | `folders/FOLDER_ID` | `folders/FOLDER_ID/key` |
| Project | `projects/PROJECT_ID` | `projects/PROJECT_ID/key` |

For enterprise-wide tags (environment, workload, team), always define at the
org level so they can be used across the entire hierarchy.

---

## Enterprise Tag Design Pattern

### Step 1 — Define keys and values at the org level

```bash
# Create the tag keys
gcloud resource-manager tags keys create environment \
  --parent=organizations/ORG_ID

gcloud resource-manager tags keys create workload \
  --parent=organizations/ORG_ID

# Create values for environment
gcloud resource-manager tags values create production \
  --parent=ORG_ID/environment
gcloud resource-manager tags values create staging \
  --parent=ORG_ID/environment
gcloud resource-manager tags values create development \
  --parent=ORG_ID/environment

# Create values for workload
gcloud resource-manager tags values create data-platform \
  --parent=ORG_ID/workload
gcloud resource-manager tags values create networking \
  --parent=ORG_ID/workload
gcloud resource-manager tags values create security \
  --parent=ORG_ID/workload
```

### Step 2 — Bind values to folders or projects

```bash
# Tag a folder as production + networking
gcloud resource-manager tags bindings create \
  --tag-value=ORG_ID/environment/production \
  --parent=//cloudresourcemanager.googleapis.com/folders/FOLDER_ID

gcloud resource-manager tags bindings create \
  --tag-value=ORG_ID/workload/networking \
  --parent=//cloudresourcemanager.googleapis.com/folders/FOLDER_ID
```

### Step 3 — Use tags in IAM conditions

```bash
gcloud organizations add-iam-policy-binding ORG_ID \
  --member="serviceAccount:networking-sa@project.iam.gserviceaccount.com" \
  --role="roles/compute.networkAdmin" \
  --condition="expression=resource.matchTag('ORG_ID/workload', 'networking'),title=Networking workload only"
```

---

## Tag Inheritance

Tags bound to a folder are inherited by all resources inside it. You don't need
to tag every project individually — tag the folder and the condition cascades down.

```
org/
  └── folders/production/          ← tag: environment=production
        └── folders/networking/    ← tag: workload=networking
              └── projects/net-prod-0   ← inherits both tags
```

A condition checking `environment=production` will match `net-prod-0` because
it inherits the tag from its parent folder.

---

## IAM Policy Version

Conditional bindings require IAM policy **version 3**. Once any conditional
binding exists in a policy, all new bindings must explicitly declare whether
they have a condition or not (use `--condition=None` for unconditional bindings).

```bash
# Unconditional binding on a v3 policy
gcloud organizations add-iam-policy-binding ORG_ID \
  --member="..." \
  --role="roles/viewer" \
  --condition=None
```

---

## FAST Usage

FAST uses org-scoped tags to scope each stage's service account permissions:

| Tag Key | Values | Purpose |
|---------|--------|---------|
| `context` | `project-factory` | Scopes project factory SA to only manage org policies on PF-tagged resources |
| `environment` | `development`, `production` | Separates dev and prod workloads |
| `org-policies` | various | Controls which org policy overrides apply |
