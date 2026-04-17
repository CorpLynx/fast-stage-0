# Feature Spec: Project Hardening Baseline (CIS Compliance)

## Goal
Ensure all core projects are provisioned with mandatory security metadata to satisfy CIS Google Cloud Computing Foundations Benchmark requirements (4.3 and 4.4).

## Stellar Engine Pattern
SE explicitly applies metadata resources to every host and service project to block manual SSH keys and force OS Login.

## Implementation Path

### 1. Update `datasets/hardened/projects/core/*.yaml`
In your modern FAST version, you can apply these directly in the project factory YAML definitions.

```yaml
# Example for datasets/hardened/projects/core/iac-0.yaml
# ... existing config ...
compute_metadata:
  block-project-ssh-keys: "true" # CIS 4.3
  enable-oslogin: "true"         # CIS 4.4
```

### 2. Port Automated Service Identity Management
SE uses a "JIT" (Just-In-Time) approach for service identities. You can ensure these are provisioned by adding them to the `services` list in your project YAMLs, which triggers the engine's internal service agent creation logic.

## Benefits
- **Identity-Based Access:** Forces all SSH access to use IAM-based OS Login instead of static, high-risk SSH keys.
- **CIS Compliance:** Directly addresses foundational security benchmark audits.
- **Hardened Perimeter:** Prevents users from "backdooring" instances with manual keys.
