# Feature Spec: Log-Based Metric Alerts (CIS Compliance)

## Goal
Implement automated security alerts in the centralized `observability` project for critical organization changes (IAM changes, Org Policy modifications, Firewall updates).

## Stellar Engine Pattern
SE uses the `cis-log-metrics` and `cis-log-alerts` modules to provision these in the bootstrap/automation projects.

## Implementation Path

### 1. Leverage `observability.tf`
Your workspace already has an `observability` project defined. We should implement these alerts there using the **Observability Factory**.

### 2. Update `datasets/hardened/observability/`
Create a `metrics.yaml` and `alerts.yaml` in your observability dataset.

**Example `metrics.yaml` pattern:**
```yaml
# datasets/hardened/observability/metrics.yaml
metrics:
  iam-change-count:
    filter: |
      protoPayload.methodName="SetIamPolicy"
      AND protoPayload.serviceName="iam.googleapis.com"
    metric_descriptor:
      metric_kind: DELTA
      value_type: INT64
```

**Example `alerts.yaml` pattern:**
```yaml
# datasets/hardened/observability/alerts.yaml
alert_policies:
  iam-change-alert:
    display_name: "Critical: IAM Policy Changed"
    combiner: OR
    conditions:
    - display_name: "IAM Change Detected"
      condition_threshold:
        filter: "metric.type=\"logging.googleapis.com/user/iam-change-count\""
        duration: "0s"
        comparison: "COMPARISON_GT"
        threshold_value: 0
    notification_channels:
    - $notification_channels:security-team
```

## Benefits
- **Real-Time Visibility:** Get notified immediately when someone modifies organization security.
- **CIS Benchmarking:** Directly satisfies CIS Google Cloud Computing Foundations Benchmark sections 2.4 - 2.11.
- **Centralization:** All alerts are managed in a single project with dedicated notification channels.
