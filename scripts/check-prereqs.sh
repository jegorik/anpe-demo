#!/usr/bin/env bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

step()  { echo -e "\n${CYAN}==>${NC} $*"; }
ok()    { echo -e "${GREEN}  ✓${NC} $*"; }
fail()  { echo -e "${RED}  ✗${NC} $*"; exit 1; }
warn()  { echo -e "${YELLOW}  !${NC} $*"; }

check_command() {
  local cmd=$1
  local install_hint=${2:-"Please install $cmd"}
  if command -v "$cmd" &>/dev/null; then
    ok "$cmd found ($(command -v "$cmd"))"
  else
    fail "$cmd not found. $install_hint"
  fi
}

echo -e "${CYAN}"
echo "╔══════════════════════════════════════╗"
echo "║   ANPE Demo — Prerequisites Check    ║"
echo "╚══════════════════════════════════════╝"
echo -e "${NC}"

step "Checking required tools..."
check_command "aws"       "Install AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
check_command "terraform" "Install Terraform: https://developer.hashicorp.com/terraform/install"
check_command "docker"    "Install Docker: https://docs.docker.com/get-docker/"
check_command "jq"        "Install jq: sudo apt install jq / brew install jq"

step "Checking AWS credentials..."
if aws sts get-caller-identity &>/dev/null; then
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  USER_ARN=$(aws sts get-caller-identity --query Arn --output text)
  REGION=$(aws configure get region 2>/dev/null || echo "not set")
  ok "AWS authenticated"
  ok "Account ID : $ACCOUNT_ID"
  ok "Identity   : $USER_ARN"
  ok "Region     : $REGION"
else
  fail "AWS credentials not configured. Run: aws configure"
fi

step "Checking Terraform version..."
TF_VERSION=$(terraform version -json | jq -r '.terraform_version')
ok "Terraform $TF_VERSION"

step "Checking Docker daemon..."
if docker info &>/dev/null; then
  ok "Docker daemon running"
else
  fail "Docker daemon not running. Start Docker and retry."
fi

echo -e "\n${GREEN}All prerequisites satisfied. Ready to deploy!${NC}"
echo -e "Next step: ${CYAN}make tf-init && make tf-plan${NC}\n"
