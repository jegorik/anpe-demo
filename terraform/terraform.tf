# ~> 1.9 means >=1.9.0, <2.0.0 — allows minor/patch upgrades, blocks breaking 2.x changes.
# Minimum 1.9 is required for stable import blocks and check blocks features.
terraform {
  required_version = "~> 1.9"

  required_providers {
    # ~> 6.0 means >=6.0.0, <7.0.0 — locks to v6 major which introduced
    # per-resource region attribute and separates SG inline rules (best practice).
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
