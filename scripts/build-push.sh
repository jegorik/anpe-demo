#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TERRAFORM_DIR="$REPO_ROOT/terraform"

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

# --- Dry-run mode: pass --dry-run to preview commands without executing them ---
# In dry-run mode the script reads Terraform outputs (safe, read-only) and prints
# every command it WOULD run, prefixed with [DRY-RUN], but skips actual execution.
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    *) fail "Unknown argument: $arg. Usage: $0 [--dry-run]" ;;
  esac
done

# run <cmd> [args...] — executes the command normally, or prints it in dry-run mode.
run() {
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}  [DRY-RUN]${NC} $*"
  else
    "$@"
  fi
}

echo -e "${CYAN}"
echo "╔══════════════════════════════════════╗"
echo "║   ANPE Demo — Build & Push to ECR    ║"
echo "╚══════════════════════════════════════╝"
echo -e "${NC}"

# --- Read Terraform outputs ---
step "Reading ECR URIs from Terraform outputs..."

if ! terraform -chdir="$TERRAFORM_DIR" output -json &>/dev/null; then
  fail "Terraform outputs not available. Run 'make tf-apply' first."
fi

ECR_API=$(terraform -chdir="$TERRAFORM_DIR" output -raw ecr_api_gateway_uri)
ECR_WORKER=$(terraform -chdir="$TERRAFORM_DIR" output -raw ecr_worker_uri)
AWS_REGION=$(terraform -chdir="$TERRAFORM_DIR" output -raw aws_region)
AWS_ACCOUNT_ID=$(terraform -chdir="$TERRAFORM_DIR" output -raw aws_account_id)

ok "api-gateway ECR : $ECR_API"
ok "worker ECR      : $ECR_WORKER"
ok "Region          : $AWS_REGION"

# --- ECR Login ---
step "Authenticating to ECR..."
run bash -c "aws ecr get-login-password --region '$AWS_REGION' \
  | docker login --username AWS --password-stdin '$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com'"
ok "ECR login successful"

# --- Build & Push api-gateway ---
step "Building api-gateway..."
run docker build -t "$ECR_API:latest" "$REPO_ROOT/services/api-gateway/"
ok "api-gateway image built"

step "Pushing api-gateway to ECR..."
run docker push "$ECR_API:latest"
ok "api-gateway pushed: $ECR_API:latest"

# --- Build & Push worker ---
step "Building worker..."
run docker build -t "$ECR_WORKER:latest" "$REPO_ROOT/services/worker/"
ok "worker image built"

step "Pushing worker to ECR..."
run docker push "$ECR_WORKER:latest"
ok "worker pushed: $ECR_WORKER:latest"

# --- Verify ---
step "Verifying images in ECR..."
API_DIGEST=$(aws ecr describe-images \
  --region "$AWS_REGION" \
  --repository-name "$(basename "$ECR_API")" \
  --query 'imageDetails[0].imageDigest' --output text 2>/dev/null || echo "N/A")
WORKER_DIGEST=$(aws ecr describe-images \
  --region "$AWS_REGION" \
  --repository-name "$(basename "$ECR_WORKER")" \
  --query 'imageDetails[0].imageDigest' --output text 2>/dev/null || echo "N/A")

ok "api-gateway digest : $API_DIGEST"
ok "worker digest      : $WORKER_DIGEST"

if [[ "$DRY_RUN" == true ]]; then
  echo -e "\n${YELLOW}Dry-run complete. No images were built or pushed.${NC}"
  echo -e "Run without --dry-run to execute: ${CYAN}./scripts/build-push.sh${NC}\n"
else
  echo -e "\n${GREEN}Images pushed successfully!${NC}\n"
  echo -e "ECS will pull the new images on next task launch."
  echo -e "Check the ALB endpoint:"
  echo -e "  ${CYAN}curl http://\$(terraform -chdir=\"$TERRAFORM_DIR\" output -raw alb_dns_name)/health${NC}\n"
fi
