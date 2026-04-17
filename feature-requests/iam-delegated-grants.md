# Feature Spec: IAM Delegated Grants (Hardening Stage 1 SAs)

## Goal
Implement "Delegated Role Grants" for Stage 1 service accounts. This ensures that even though these accounts have `organizationIamAdmin` permissions, they can only grant a specific, pre-approved list of roles. This prevents a compromised CI/CD account from elevating its own privileges to Org Admin.

## Stellar Engine Pattern
SE uses an IAM condition with `api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', [])` to restrict the blast radius of automation identities.

## Implementation Path

### 1. Update `datasets/hardened/organization/iam.yaml`
Add a conditional binding for the resource management service accounts.

```yaml
iam_by_principals_conditional:
  # Stage 1: Resource Management (Resman)
  $iam_principals:service_accounts/iac-0/iac-org-rw:
    - role: $custom_roles:organization_iam_admin
      condition:
        title: delegated_role_grants
        description: Restrict roles this SA can grant to others.
        expression: |
          api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly([
            'roles/accesscontextmanager.policyAdmin',
            'roles/cloudasset.viewer',
            'roles/compute.orgFirewallPolicyAdmin',
            'roles/compute.xpnAdmin',
            'roles/orgpolicy.policyAdmin',
            'roles/orgpolicy.policyViewer',
            'roles/resourcemanager.organizationViewer',
            'organizations/1041701195417/roles/tenantNetworkAdmin'
          ])
```

## Benefits
- **Zero-Trust for CI/CD:** Automation can manage its specific domain (Networking, Security) but cannot grant itself `roles/owner` or `roles/resourcemanager.organizationAdmin`.
- **Compliance:** Aligns with CIS and FedRAMP "Least Privilege" requirements.
