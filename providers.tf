provider "google" {
  user_project_override = true
  billing_project       = "fpoc-seed-bootstrap"
}

provider "google-beta" {
  user_project_override = true
  billing_project       = "fpoc-seed-bootstrap"
}
