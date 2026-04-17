provider "google" {
  user_project_override = true
  billing_project       = "fpoc3-prod-iac-core-0"
}

provider "google-beta" {
  user_project_override = true
  billing_project       = "fpoc3-prod-iac-core-0"
}
