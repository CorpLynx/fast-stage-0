terraform {
  cloud {
    organization = "corplynx-lab"
    workspaces {
      name = "fast-stage-0"
    }
  }
}
