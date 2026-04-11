/**
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import {
  for_each = toset(local.organization.id != null ? var.org_policies_imports : [])
  id       = "organizations/${local.organization_id}/policies/${each.key}"
  to       = module.organization-iam[0].google_org_policy_policy.default[each.key]
}

import {
  id = "fpoc2-prod-audit-logs-0"
  to = module.factory.module.projects["log-0"].google_project.project[0]
}

import {
  id = "organizations/1041701195417/customConstraints/custom.storageRequireBucketObjectVersionningV2"
  to = module.organization-iam[0].google_org_policy_custom_constraint.constraint["custom.storageRequireBucketObjectVersionningV2"]
}

import {
  id = "organizations/1041701195417/customConstraints/custom.iamDisableAdminServiceAccountV2"
  to = module.organization-iam[0].google_org_policy_custom_constraint.constraint["custom.iamDisableAdminServiceAccountV2"]
}

import {
  id = "organizations/1041701195417/customConstraints/custom.iamDisableProjectServiceAccountImpersonationRolesV2"
  to = module.organization-iam[0].google_org_policy_custom_constraint.constraint["custom.iamDisableProjectServiceAccountImpersonationRolesV2"]
}
