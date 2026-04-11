org_policies_imports = [
  "essentialcontacts.allowedContactDomains",
  "iam.allowedPolicyMemberDomains",
  "compute.restrictProtocolForwardingCreationForTypes",
  "iam.disableServiceAccountKeyCreation",
  "storage.uniformBucketLevelAccess",
  "iam.disableServiceAccountKeyUpload",
  "compute.setNewProjectDefaultToZonalDNSOnly",
  "iam.automaticIamGrantsForDefaultServiceAccounts",
]

# Uncomment after WIF pool is created in iac-0 project
# factories_config = {
#   paths = {
#     cicd_workflows = "cicd-workflows.yaml"
#   }
# }
