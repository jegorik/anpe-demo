# Runbook — ANPE Demo Deployment

## Overview

This runbook covers:

1. [Local development](#1-local-development-docker-compose)
2. [AWS deployment](#2-aws-deployment-ecs-fargate)
3. [Teardown](#3-teardown)
4. [Troubleshooting](#4-troubleshooting)

---

## 1. Local Development (Docker Compose)

### Prerequisites

| Tool           | Version | Install                               |
|----------------|---------|---------------------------------------|
| Docker         | ≥ 24    | <https://docs.docker.com/get-docker/> |
| Docker Compose | ≥ 2.20  | bundled with Docker Desktop           |

### Start services

```bash
make local-up
# or: docker compose up --build -d
```

Services will be available at:

- `http://localhost:8080/health` — api-gateway health check
- `http://localhost:8080/metrics` — api-gateway Prometheus metrics
- `http://localhost:9090/metrics` — worker Prometheus metrics

### Example API calls

```bash
# Submit a task
curl -X POST http://localhost:8080/tasks \
  -H "Content-Type: application/json" \
  -d '{"payload": "process-this"}'
# → {"task_id": "...", "status": "queued"}

# Check task status
curl http://localhost:8080/tasks/<task_id>

# List all tasks
curl http://localhost:8080/tasks
```

### Stop services

```bash
make local-down
# or: docker compose down
```

---

## 2. AWS Deployment (ECS Fargate)

### Prerequisites

| Tool      | Min version | Install                                                                         |
|-----------|-------------|---------------------------------------------------------------------------------|
| AWS CLI   | v2          | <https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html> |
| Terraform | 1.9+        | <https://developer.hashicorp.com/terraform/install>                             |
| Docker    | 24+         | <https://docs.docker.com/get-docker/>                                           |
| jq        | any         | `sudo apt install jq` / `brew install jq`                                       |

Verify everything is in order:

```bash
make check-prereqs
```

All checks must pass (green ✓) before proceeding.

### Step 1 — Configure Terraform variables

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit `terraform/terraform.tfvars`:

```hcl
project_name = "anpe"           # prefix for all AWS resource names
aws_region   = "eu-central-1"  # your target region

# Leave image URIs empty on first deploy — ECR repos are created by Terraform.
# Populate them after running build-push (Step 3).
api_gateway_image = ""
worker_image      = ""
```

> `terraform.tfvars` is in `.gitignore` — it will never be committed to the repo.

### Step 2 — Preview infrastructure

```bash
make tf-plan
```

Expected output: **29 resources** to be created (VPC, 2 subnets, IGW, route table,
2 route table associations, 2 security groups + 5 SG rules, 2 ECR repos + 2 lifecycle policies,
IAM role + policy attachment + logs inline policy,
ALB + target group + listener, ECS cluster + 2 task definitions + 2 services).

Review the plan and confirm there are no unexpected changes.

### Step 3 — Apply infrastructure

```bash
make tf-apply
# or: terraform -chdir=terraform apply
```

This takes approximately **2–4 minutes**. Terraform creates all AWS resources and
prints output values at the end:

```text
Outputs:
  alb_dns_name         = "anpe-alb-123456789.eu-central-1.elb.amazonaws.com"
  ecr_api_gateway_uri  = "123456789.dkr.ecr.eu-central-1.amazonaws.com/anpe-api-gateway"
  ecr_worker_uri       = "123456789.dkr.ecr.eu-central-1.amazonaws.com/anpe-worker"
  ecs_cluster_name     = "anpe-cluster"
  aws_account_id       = "123456789012"
  aws_region           = "eu-central-1"
```

### Step 4 — Build and push images to ECR

```bash
# Preview what will run without actually building/pushing
./scripts/build-push.sh --dry-run

# Execute for real
make build-push
# or: ./scripts/build-push.sh
```

The script:

1. Reads ECR URIs from `terraform output`
2. Authenticates Docker to ECR
3. Builds both images locally
4. Pushes to ECR
5. Verifies image digests in ECR

### Step 5 — Verify the deployment

```bash
# Get ALB DNS name
ALB=$(terraform -chdir=terraform output -raw alb_dns_name)
echo "ALB: http://$ALB"

# Health check (may take 1–2 min for ECS tasks to start and pass health checks)
curl http://$ALB/health
# Expected: {"status":"ok","service":"api-gateway"}

# Submit a task through the ALB
curl -X POST http://$ALB/tasks \
  -H "Content-Type: application/json" \
  -d '{"payload": "hello-from-aws"}'
```

If the ALB returns 503, the ECS task is still starting or health checks are failing.
Wait 1–2 minutes and retry.

### Useful AWS CLI commands

```bash
# Check ECS service status
aws ecs describe-services \
  --cluster anpe-cluster \
  --services anpe-api-gateway anpe-worker \
  --query 'services[*].{name:serviceName,status:status,running:runningCount,desired:desiredCount}'

# Check ECS task health
aws ecs list-tasks --cluster anpe-cluster --service-name anpe-api-gateway
aws ecs describe-tasks --cluster anpe-cluster \
  --tasks $(aws ecs list-tasks --cluster anpe-cluster --service-name anpe-api-gateway \
            --query 'taskArns[0]' --output text)

# Tail CloudWatch logs
aws logs tail /ecs/anpe/api-gateway --follow
aws logs tail /ecs/anpe/worker --follow

# List ECR images
aws ecr describe-images \
  --repository-name anpe-api-gateway \
  --query 'imageDetails[*].{tag:imageTags[0],digest:imageDigest,pushed:imagePushedAt}' \
  --output table
```

---

## 3. Teardown

```bash
make destroy
```

This will prompt for confirmation before destroying all resources.
Approximate teardown time: **3–5 minutes**.

> **Important:** ECR images are tracked by Terraform state and will be deleted
> along with the repositories. If you want to keep the images, pull them locally
> first or push them to another registry.

---

## 4. Troubleshooting

### ECS service stuck in PENDING

**Symptom:** `runningCount = 0`, tasks never become RUNNING.

**Causes and fixes:**

1. **Image pull failure** — verify the ECR repo exists and the image was pushed:

   ```bash
   aws ecr describe-images --repository-name anpe-api-gateway
   ```

   If empty, run `make build-push`.

2. **IAM permissions** — the ECS task execution role may lack ECR pull access.
   Check that `AmazonECSTaskExecutionRolePolicy` is attached:

   ```bash
   aws iam list-attached-role-policies --role-name anpe-ecs-task-execution
   ```

3. **No public IP** — tasks need `assign_public_ip = true` to reach ECR without NAT.
   Verify this in `terraform/ecs.tf` (`network_configuration` block).

### ALB returns 503 Service Unavailable

**Symptom:** `curl http://$ALB/health` → 503.

The target group has no healthy targets. Check:

```bash
# Target group health
aws elbv2 describe-target-health \
  --target-group-arn $(terraform -chdir=terraform output -json | jq -r '.alb_dns_name // empty')
```

Most likely the ECS task is still starting (allow 1–2 min) or the health check
on `/health` is failing. Check CloudWatch logs:

```bash
aws logs tail /ecs/anpe/api-gateway --follow
```

### `terraform apply` fails — resource already exists

If you previously created ECR repos manually (before Terraform was set up):

```bash
# Option A — delete manually-created repos first (loses any images in them)
aws ecr delete-repository --repository-name anpe-api-gateway --force
aws ecr delete-repository --repository-name anpe-worker --force
terraform -chdir=terraform apply

# Option B — import existing repos into Terraform state
terraform -chdir=terraform import aws_ecr_repository.api_gateway anpe-api-gateway
terraform -chdir=terraform import aws_ecr_repository.worker anpe-worker
terraform -chdir=terraform apply
```

### `make build-push` fails — ECR login error

```text
Error: Cannot perform an interactive login from a non TTY device
```

AWS credentials are not configured. Run:

```bash
aws configure
# or export AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_DEFAULT_REGION
make check-prereqs  # verify credentials are valid
```

### Terraform outputs not available

```text
Error: No value for required variable
```

Terraform has not been applied yet, or state was lost. Run:

```bash
make tf-apply
terraform -chdir=terraform output
```

---

## Cost Estimate

Resources created by `make deploy` in `eu-central-1`:

| Resource                                   | Approx cost        |
|--------------------------------------------|--------------------|
| ECS Fargate (2 tasks × 0.25 vCPU × 0.5 GB) | ~$0.03/hour        |
| ALB                                        | ~$0.008/hour + LCU |
| ECR storage (≤ 5 small images)             | ~$0.01/GB/month    |
| CloudWatch Logs                            | ~$0.50/GB ingested |
| VPC, IGW, route tables, SGs                | Free               |
| **Total (idle, no traffic)**               | **~$1–2/day**      |

Run `make destroy` when done to avoid ongoing charges.
