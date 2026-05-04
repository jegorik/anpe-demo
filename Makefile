.PHONY: help local-up local-down check-prereqs tf-init tf-plan tf-apply tf-destroy build-push deploy destroy \
        test test-unit test-infra test-integration

TERRAFORM_DIR := terraform
SCRIPTS_DIR   := scripts

# Default target
help:
	@echo ""
	@echo "ANPE Demo — Available commands:"
	@echo ""
	@echo "  Testing:"
	@echo "    make test            Run all test suites (unit + infra + integration)"
	@echo "    make test-unit       Unit tests for api-gateway and worker"
	@echo "    make test-infra      Infrastructure tests (terraform validate, shellcheck)"
	@echo "    make test-integration Integration tests (starts Docker Compose automatically)"
	@echo ""
	@echo "  Local development:"
	@echo "    make local-up        Build and start services with Docker Compose"
	@echo "    make local-down      Stop and remove local containers"
	@echo ""
	@echo "  AWS deployment:"
	@echo "    make check-prereqs   Verify required tools and AWS credentials"
	@echo "    make tf-init         Initialize Terraform (downloads providers)"
	@echo "    make tf-plan         Show infrastructure changes without applying"
	@echo "    make tf-apply        Create/update AWS infrastructure"
	@echo "    make build-push      Build Docker images and push to ECR"
	@echo "    make deploy          Full deploy: tf-apply + build-push"
	@echo "    make destroy         Destroy all AWS resources (asks confirmation)"
	@echo ""
	@echo "  First-time setup:"
	@echo "    1. cp $(TERRAFORM_DIR)/terraform.tfvars.example $(TERRAFORM_DIR)/terraform.tfvars"
	@echo "    2. Edit $(TERRAFORM_DIR)/terraform.tfvars with your values"
	@echo "    3. make check-prereqs"
	@echo "    4. make deploy"
	@echo ""

# ── Local ──────────────────────────────────────────────────────────────────────

local-up:
	docker compose up --build -d

local-down:
	docker compose down

# ── Testing ────────────────────────────────────────────────────────────────────

# Run all suites with logging. Log saved to logs/test-<timestamp>.log
test:
	@bash $(SCRIPTS_DIR)/run-tests.sh

# Unit tests only — no Docker, no AWS, no Terraform needed
test-unit:
	@bash $(SCRIPTS_DIR)/run-tests.sh --unit

# Infrastructure tests — requires terraform + shellcheck installed
test-infra:
	@bash $(SCRIPTS_DIR)/run-tests.sh --infra

# Integration tests — starts Docker Compose, runs tests, stops compose
test-integration:
	@bash $(SCRIPTS_DIR)/run-tests.sh --integration

# ── AWS ────────────────────────────────────────────────────────────────────────

check-prereqs:
	@bash $(SCRIPTS_DIR)/check-prereqs.sh

tf-init:
	@echo "==> Initializing Terraform..."
	@test -f $(TERRAFORM_DIR)/terraform.tfvars || \
		(echo "ERROR: terraform/terraform.tfvars not found. Run:" && \
		 echo "  cp terraform/terraform.tfvars.example terraform/terraform.tfvars" && \
		 echo "  # then edit terraform/terraform.tfvars with your values" && exit 1)
	terraform -chdir=$(TERRAFORM_DIR) init

tf-plan: tf-init
	terraform -chdir=$(TERRAFORM_DIR) plan

tf-apply: tf-init
	terraform -chdir=$(TERRAFORM_DIR) apply -auto-approve
	@echo ""
	@echo "Infrastructure ready. Run 'make build-push' to push images to ECR."

build-push:
	@bash $(SCRIPTS_DIR)/build-push.sh

deploy: tf-apply build-push
	@echo ""
	@echo "==> Deployment complete!"
	@echo "ALB endpoint:"
	@terraform -chdir=$(TERRAFORM_DIR) output -raw alb_dns_name
	@echo ""

destroy:
	@echo ""
	@echo "WARNING: This will destroy ALL AWS resources created by Terraform."
	@read -p "Type 'yes' to confirm: " confirm && [ "$$confirm" = "yes" ] || (echo "Aborted." && exit 1)
	terraform -chdir=$(TERRAFORM_DIR) destroy -auto-approve
	@echo ""
	@echo "All resources destroyed."
