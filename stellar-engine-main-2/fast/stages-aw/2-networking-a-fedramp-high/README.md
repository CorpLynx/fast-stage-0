# FedRAMP High Network

This stage deploys the networking infrastructure recommended with an Assured Workload FedRAMP High environment.

<!-- BEGIN TOC -->
- [Variables](#variables)
- [Outputs](#outputs)
<!-- END TOC -->

---
<!-- BEGIN TFDOC -->
## Variables

| name | description | type | required | default |
|---|---|:---:|:---:|:---:|
| [alert_email](variables.tf#L16) | Email to receive log alerts. | <code>string</code> | ✓ |  |
| [automation](variables.tf#L21) | Automation resources created by the bootstrap stage. | <code title="object&#40;&#123;&#10;  outputs_bucket &#61; string&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> | ✓ |  |
| [billing_account](variables.tf#L29) | Billing account id. If billing account is not part of the same org set `is_org_level` to false. | <code title="object&#40;&#123;&#10;  id           &#61; string&#10;  is_org_level &#61; optional&#40;bool, true&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> | ✓ |  |
| [envs_folders](variables.tf#L60) | List of environments to be created for projects to go into. | <code title="map&#40;object&#40;&#123;&#10;  admin &#61; string&#10;&#125;&#41;&#41;">map&#40;object&#40;&#123;&#8230;&#125;&#41;&#41;</code> | ✓ |  |
| [folder_ids](variables.tf#L94) | Folders to be used for the networking resources in folders/nnnnnnnnnnn format. If null, folder will be created. | <code title="object&#40;&#123;&#10;  networking &#61; string&#10;  envs       &#61; optional&#40;map&#40;string&#41;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> | ✓ |  |
| [organization](variables.tf#L114) | Organization details. | <code title="object&#40;&#123;&#10;  domain      &#61; string&#10;  id          &#61; number&#10;  customer_id &#61; string&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> | ✓ |  |
| [prefix](variables.tf#L130) | Prefix used for resources that need unique names. Use 9 characters or less. | <code>string</code> | ✓ |  |
| [tenant_accounts](variables.tf#L186) | Base Tenant accounts that are created for each folder, provided as a combination of environment and tenant. | <code title="map&#40;object&#40;&#123;&#10;  tenant          &#61; string&#10;  env             &#61; string&#10;  main_project    &#61; string&#10;  admin_principal &#61; string&#10;&#125;&#41;&#41;">map&#40;object&#40;&#123;&#8230;&#125;&#41;&#41;</code> | ✓ |  |
| [custom_roles](variables.tf#L42) | Custom roles defined at the org level, in key => id format. | <code title="object&#40;&#123;&#10;  service_project_network_admin &#61; string&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>null</code> |
| [dns](variables.tf#L50) | DNS configuration. | <code title="object&#40;&#123;&#10;  enable_logging &#61; optional&#40;bool, true&#41; &#35; CIS Compliance Benchmark 2.12&#10;  resolvers      &#61; optional&#40;list&#40;string&#41;, &#91;&#93;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [essential_contacts](variables.tf#L67) | Email used for essential contacts, unset if null. | <code>string</code> |  | <code>null</code> |
| [factories_config](variables.tf#L73) | Configuration for network resource factories. | <code title="object&#40;&#123;&#10;  data_dir              &#61; optional&#40;string, &#34;data&#34;&#41;&#10;  dns_policy_rules_file &#61; optional&#40;string, &#34;data&#47;dns-policy-rules.yaml&#34;&#41;&#10;  firewall_policy_name  &#61; optional&#40;string, &#34;net-default&#34;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code title="&#123;&#10;  data_dir &#61; &#34;data&#34;&#10;&#125;">&#123;&#8230;&#125;</code> |
| [gcp_ranges](variables.tf#L103) | GCP address ranges in name => range format. | <code>map&#40;string&#41;</code> |  | <code title="&#123;&#10;  gcp_dev_primary             &#61; &#34;10.68.0.0&#47;16&#34;&#10;  gcp_landing_landing_primary &#61; &#34;10.200.0.0&#47;16&#34;&#10;  gcp_dmz_primary             &#61; &#34;10.64.128.0&#47;24&#34;&#10;  gcp_prod_primary            &#61; &#34;10.72.0.0&#47;16&#34;&#10;&#125;">&#123;&#8230;&#125;</code> |
| [outputs_location](variables.tf#L124) | Path where providers and tfvars files for the following stages are written. Leave empty to disable. | <code>string</code> |  | <code>null</code> |
| [psa_ranges](variables.tf#L141) | IP ranges used for Private Service Access (e.g. CloudSQL). Ranges is in name => range format. | <code title="object&#40;&#123;&#10;  dev &#61; optional&#40;list&#40;object&#40;&#123;&#10;    ranges         &#61; map&#40;string&#41;&#10;    export_routes  &#61; optional&#40;bool, false&#41;&#10;    import_routes  &#61; optional&#40;bool, false&#41;&#10;    peered_domains &#61; optional&#40;list&#40;string&#41;, &#91;&#93;&#41;&#10;  &#125;&#41;&#41;, &#91;&#93;&#41;&#10;  prod &#61; optional&#40;list&#40;object&#40;&#123;&#10;    ranges         &#61; map&#40;string&#41;&#10;    export_routes  &#61; optional&#40;bool, false&#41;&#10;    import_routes  &#61; optional&#40;bool, false&#41;&#10;    peered_domains &#61; optional&#40;list&#40;string&#41;, &#91;&#93;&#41;&#10;  &#125;&#41;&#41;, &#91;&#93;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [regions](variables.tf#L161) | Region definitions. | <code title="object&#40;&#123;&#10;  primary &#61; string&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code title="&#123;&#10;  primary &#61; &#34;us-east4&#34;&#10;&#125;">&#123;&#8230;&#125;</code> |
| [service_accounts](variables.tf#L172) | Automation service accounts in name => email format. | <code title="object&#40;&#123;&#10;  data-platform-dev    &#61; string&#10;  data-platform-prod   &#61; string&#10;  gke-dev              &#61; string&#10;  gke-prod             &#61; string&#10;  project-factory-dev  &#61; string&#10;  project-factory-prod &#61; string&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>null</code> |

## Outputs

| name | description | sensitive |
|---|---|:---:|
| [host_project_ids](outputs.tf#L60) | Network project ids. |  |
| [host_project_numbers](outputs.tf#L65) | Network project numbers. |  |
| [tfvars](outputs.tf#L70) | Terraform variables file for the following stages. | ✓ |
<!-- END TFDOC -->
