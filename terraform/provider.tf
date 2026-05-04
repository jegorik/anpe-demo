# Region is driven by variable — makes the entire config portable across
# any AWS account without touching provider code.
provider "aws" {
  region = var.aws_region
}

# Used in outputs to surface the active account ID, which helps verify
# that the correct AWS account/profile is being used before applying.
data "aws_caller_identity" "current" {}

# Fetches AZs dynamically to avoid hardcoding region-specific names
# (e.g. "eu-central-1a"). Subnets are distributed across these AZs for HA.
data "aws_availability_zones" "available" {
  state = "available"
}
