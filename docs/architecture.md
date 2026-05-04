# Architecture — ANPE Demo

## AWS Infrastructure Overview

```text
                         Internet
                             │
                    ┌────────▼────────┐
                    │  Route 53 / DNS │  (ALB DNS name from Terraform output)
                    └────────┬────────┘
                             │  :80 HTTP
                    ┌────────▼────────────────────────────────────┐
                    │       Application Load Balancer             │
                    │       (internet-facing, 2 AZs)              │
                    │       Security Group: allow 0.0.0.0/0 → 80  │
                    └───────────────┬─────────────────────────────┘
                                    │  forward to Target Group
                    ┌───────────────▼─────────────────────────────┐
                    │          AWS ECS Fargate Cluster            │
                    │                                             │
                    │  ┌──────────────────┐  ┌─────────────────┐  │
                    │  │  api-gateway     │  │    worker       │  │
                    │  │  task · :8080    │  │  task · :9090   │  │
                    │  │  256 CPU / 512MB │  │ 256 CPU / 512MB │  │
                    │  └────────┬─────────┘  └────────┬────────┘  │
                    │           │                     │           │
                    └───────────┼─────────────────────┼───────────┘
                                │                     │
              ECS Security Group (ingress: ALB→8080, self→9090; egress: all)
                                │                     │
                    ┌───────────▼─────────────────────▼───────────┐
                    │         Custom VPC  10.0.0.0/16             │
                    │                                             │
                    │  ┌───────────────┐   ┌────────────────┐     │
                    │  │ Public Subnet │   │ Public Subnet  │     │
                    │  │ 10.0.1.0/24   │   │ 10.0.2.0/24    │     │
                    │  │ eu-central-1a │   │ eu-central-1b  │     │
                    │  └───────┬───────┘   └────────┬───────┘     │
                    │          └────────┬───────────┘             │
                    │                   │                         │
                    │       ┌───────────▼───────────┐             │
                    │       │   Internet Gateway    │             │
                    │       │   Route: 0.0.0.0/0 →  │             │
                    │       └───────────────────────┘             │
                    └─────────────────────────────────────────────┘
                                        │
                              ┌─────────▼──────────┐
                              │    AWS ECR         │
                              │  anpe-api-gateway  │
                              │  anpe-worker       │
                              │  (keep last 5 imgs)│
                              └────────────────────┘

Supporting services (not in diagram):
  - CloudWatch Logs  → /ecs/anpe/api-gateway, /ecs/anpe/worker
  - IAM Role         → ecs-task-execution (ECR pull + CW write)
```

> **Note:** The AZ names in the diagram (`eu-central-1a`/`eu-central-1b`) reflect the default
> `aws_region = "eu-central-1"`. Terraform resolves AZs dynamically via
> `data.aws_availability_zones.available`, so any region works — the first two available AZs
> are selected automatically.

## Resource Inventory

| Terraform Resource | AWS Resource | Purpose |
| -------------------- | -------------- | --------- |
| `aws_vpc.main` | VPC `10.0.0.0/16` | Network isolation |
| `aws_subnet.public[0,1]` | Public subnets in 2 AZs | HA placement for ALB + tasks |
| `aws_internet_gateway.main` | IGW | Outbound internet for tasks and ALB |
| `aws_route_table.public` | Route table | `0.0.0.0/0 → IGW` |
| `aws_route_table_association[0,1]` | RT associations | Link each public subnet to the route table |
| `aws_security_group.alb` | ALB SG | Ingress: `0.0.0.0/0:80` |
| `aws_security_group.ecs` | ECS SG | Ingress: ALB→8080, self→9090; Egress: all |
| `aws_vpc_security_group_*_rule` (5) | SG rules | Separate rule resources per AWS provider v6 best practice |
| `aws_ecr_repository.api_gateway` | ECR repo | Stores api-gateway images |
| `aws_ecr_repository.worker` | ECR repo | Stores worker images |
| `aws_ecr_lifecycle_policy.*` | Lifecycle policy (×2) | Expires images when count > `ecr_image_retention_count` (default 5) |
| `aws_iam_role.ecs_task_execution` | IAM Role | Allows tasks to pull images and write logs |
| `aws_iam_role_policy_attachment.ecs_task_execution` | Policy attachment | Attaches `AmazonECSTaskExecutionRolePolicy` |
| `aws_iam_role_policy.ecs_task_execution_logs` | Inline policy | Grants `logs:CreateLogGroup` (not included in the managed policy) |
| `aws_lb.main` | ALB | Distributes HTTP traffic across tasks |
| `aws_lb_target_group.api_gateway` | Target Group | Health-checks tasks on `GET /health` |
| `aws_lb_listener.http` | Listener :80 | Forwards to target group |
| `aws_ecs_cluster.main` | ECS Cluster | Container Insights enabled |
| `aws_ecs_task_definition.api_gateway` | Task def | FARGATE, awsvpc, 256 CPU / 512 MiB |
| `aws_ecs_task_definition.worker` | Task def | FARGATE, awsvpc, 256 CPU / 512 MiB |
| `aws_ecs_service.api_gateway` | ECS Service | 1 replica, attached to ALB |
| `aws_ecs_service.worker` | ECS Service | 1 replica, internal only (no LB) |

## Design Decisions

### Custom VPC instead of the AWS Default VPC

The default VPC is shared across all services in an account, may have been modified,
and teaches nothing about networking. A custom VPC demonstrates knowledge of CIDR planning,
IGW, route tables, and subnet design — all of which are core Cloud Engineer skills.

### Public Subnets + `assign_public_ip = true` instead of Private Subnets + NAT Gateway

ECS Fargate tasks need to reach ECR (image pull) and CloudWatch (logs). The standard
production pattern uses private subnets with a NAT Gateway, but NAT Gateways cost ~$32/month
plus data transfer. For a demo project the trade-off is:

- **Cost:** $0 extra vs ~$32/month
- **Security:** Tasks have public IPs, but the ECS Security Group allows **no inbound from
  the internet** — only from the ALB Security Group. The public IP is used only for
  *outbound* traffic (ECR, CW).
- **Production note:** In a production setup, replace public subnets with private subnets
  and add a NAT Gateway (or VPC Gateway Endpoints for ECR/S3/CW to eliminate NAT costs).

### Fargate instead of EC2 Launch Type

Fargate removes EC2 instance management (patching, scaling, capacity planning).
For a demo/microservices workload this is the right default — pay per task-second,
no idle instance costs, no AMI maintenance.

### Separate `aws_vpc_security_group_ingress_rule` / `egress_rule` Resources

AWS provider v6 best practice. Inline `ingress`/`egress` blocks inside
`aws_security_group` have historically caused perpetual diffs and merge conflicts
in team environments. Separate rule resources have unique IDs, support tagging,
and compose cleanly across modules.

### `awslogs-create-group = true` in Task Definitions

Avoids the need to pre-create CloudWatch Log Groups as a separate Terraform resource.
ECS creates the group on first task start. Keeps the Terraform config smaller without
sacrificing observability.

### `image_tag_mutability = "MUTABLE"` on ECR

Acceptable for a CI/CD demo where `:latest` is overwritten on every push.
In production, use `IMMUTABLE` to enforce image provenance and prevent accidental
tag overwrites — each build would push a unique `sha-<commit>` tag.

### Worker Port 9090 in ECS Security Group (self-referencing rule)

The `ecs_prometheus_9090` ingress rule references the ECS SG itself
(`referenced_security_group_id = aws_security_group.ecs.id`). This means any ECS
task inside the SG can scrape port 9090 of any other task in the same SG —
which is exactly how Prometheus will reach the worker in Module 6.

## CI/CD Flow

```text
git push → main (or PR)
     │
     ▼
GitHub Actions CI  (parallel jobs)
  ├── lint-python    ← flake8 on services/
  ├── lint-terraform  ← fmt-check + init -backend=false + validate + tflint
  ├── lint-shell     ← shellcheck on scripts/
  ├── test-unit      ← pytest services/*/test_main.py  (14+7 tests, JUnit XML)
  └── test-infra     ← pytest tests/test_infrastructure.py  (17 tests)

All 5 jobs must pass before:
     │
     ▼
  build-push
     ├── docker buildx build
     ├── tag: sha-<commit>, latest
     └── push → ghcr.io/<owner>/anpe-{api-gateway,worker}

(Manual step for AWS)
     │
     ▼
scripts/build-push.sh
  ├── reads ECR URIs from terraform output
  ├── docker build → tag with ECR URI
  └── docker push → ECR
```

## Service Communication

The two services are **independent** — api-gateway does not call the worker.
Each exposes its own Prometheus metrics endpoint for future scraping by Prometheus (Module 6).

| Environment               | api-gateway             | worker                                                      |
|---------------------------|-------------------------|-------------------------------------------------------------|
| Local (Compose)           | `http://localhost:8080` | `http://localhost:9090/metrics`                             |
| k3s                       | NodePort `:30080`       | ClusterIP `:9090` (internal only)                           |
| AWS ECS                   | via ALB DNS             | no public endpoint (ECS SG only allows ALB→8080, self→9090) |
