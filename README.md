# ANPE Demo — Automated Network Processing Engine

A cloud-native microservices demo platform built as a practical Cloud Engineer portfolio.  
Covers the full lifecycle: local development → CI/CD → Kubernetes → AWS production deployment.

> **Stack:** Docker · GitHub Actions · k3s · Terraform · AWS ECS Fargate · ECR · ALB

---

## Service Architecture

```text
  Internet
     │
     ▼
┌──────────────────────────────────────┐
│  Application Load Balancer :80       │  AWS / k3s NodePort :30080
└──────────────────┬───────────────────┘
                   │
                   ▼
        ┌──────────────────┐
        │   api-gateway    │  :8080
        │                  │
        │  POST /tasks     │
        │  GET  /health    │
        │  GET  /metrics   │
        └────────┬─────────┘
                 │  internal call
                 ▼
        ┌──────────────────┐
        │     worker       │  :9090
        │                  │
        │  processes tasks │
        │  GET /metrics    │◀──── Prometheus scraping (Module 6)
        └──────────────────┘
```

## Tech Stack

| Layer           | Tool                                         |
|-----------------|----------------------------------------------|
| Language        | Python 3.13 · FastAPI · uvicorn              |
| Containers      | Docker 29 · Docker Compose                   |
| Registry        | GHCR (CI) · AWS ECR (production)             |
| CI/CD           | GitHub Actions (lint + test + build + push)  |
| Testing         | pytest · httpx · TestClient                  |
| Orchestration   | k3s v1.31 (self-hosted on Proxmox VM)        |
| Cloud IaC       | Terraform ~>1.9 · AWS provider ~>6.0         |
| Cloud runtime   | AWS ECS Fargate · ALB · VPC                  |
| Observability   | Prometheus · Grafana (Module 6)              |

## Progress

| Module | Topic                                         | Status                                                        |
|--------|-----------------------------------------------|---------------------------------------------------------------|
| 1      | Git workflow & project structure              | ✅ Done                                                       |
| 2      | Docker: Dockerfiles + Compose + GHCR push     | ✅ Done                                                       |
| 3      | GitHub Actions CI: lint + test + build + push | ✅ Done                                                       |
| 4      | Kubernetes: k3s manifests + deployment        | ✅ Done                                                       |
| 5      | CD to k3s via GitHub Actions                  | ⏭ Skipped (home firewall blocks inbound SSH from GHA runners) |
| 6      | Observability: Prometheus + Grafana           | 🔜 Next                                                       |
| 7      | AWS: ECR + ECS Fargate via Terraform          | ✅ Done                                                       |

## Repository Structure

```text
anpe-demo/
├── .github/
│   └── workflows/
│       └── ci.yml            # Lint → build → push to GHCR on every push to main
├── services/
│   ├── api-gateway/          # FastAPI REST service (port 8080)
│   │   ├── Dockerfile
│   │   ├── main.py
│   │   ├── requirements.txt
│   │   └── test_main.py      # 14 unit tests (FastAPI TestClient)
│   └── worker/               # Background task processor (port 9090)
│       ├── Dockerfile
│       ├── main.py
│       ├── requirements.txt
│       └── test_main.py      # 7 unit tests (mock-based)
├── k8s/
│   ├── namespace.yml         # Namespace: anpe
│   ├── api-gateway.yml       # Deployment + NodePort :30080
│   └── worker.yml            # Deployment + ClusterIP :9090
├── terraform/
│   ├── terraform.tf          # Provider versions
│   ├── provider.tf           # AWS provider + data sources
│   ├── variables.tf          # Input variables
│   ├── vpc.tf                # VPC, subnets, IGW, route table
│   ├── security_groups.tf    # ALB SG + ECS SG (separate rule resources)
│   ├── main.tf               # ECR repositories + lifecycle policies
│   ├── iam.tf                # ECS Task Execution Role
│   ├── alb.tf                # ALB + target group + HTTP listener
│   ├── ecs.tf                # ECS cluster + task definitions + services
│   ├── outputs.tf            # ECR URIs, ALB DNS, cluster name
│   └── terraform.tfvars.example  # Template — copy and fill before deploying
├── tests/
│   ├── requirements.txt      # httpx + pytest for integration/infra tests
│   ├── test_integration.py   # 12 integration tests (live Docker Compose)
│   └── test_infrastructure.py # 17 infra tests (terraform validate, shellcheck)
├── scripts/
│   ├── check-prereqs.sh      # Verify aws/terraform/docker/jq + AWS auth
│   ├── build-push.sh         # ECR login → docker build → push (--dry-run flag)
│   └── run-tests.sh          # Full test runner with log file + summary
├── pytest.ini                # pytest markers and testpaths
├── docs/
│   ├── architecture.md       # AWS infrastructure diagram + design decisions
│   └── runbook.md            # Step-by-step deploy and teardown guide
├── docker-compose.yml        # Local multi-service orchestration
└── Makefile                  # Developer shortcuts (see `make help`)
```

## Quick Start

### Local (Docker Compose)

```bash
git clone https://github.com/<your-username>/anpe-demo.git
cd anpe-demo

make local-up
# api-gateway → http://localhost:8080/health
# worker      → http://localhost:9090/metrics

# Submit a task
curl -X POST http://localhost:8080/tasks \
  -H "Content-Type: application/json" \
  -d '{"payload": "hello"}'
```

### AWS (Terraform + ECS Fargate)

```bash
# 1. Prerequisites
make check-prereqs

# 2. Configure
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# edit terraform/terraform.tfvars — set aws_region, project_name, etc.

# 3. Preview infrastructure (29 resources)
make tf-plan

# 4. Deploy (creates VPC, ALB, ECR, ECS cluster, IAM)
make deploy

# 5. Verify
curl http://$(terraform -chdir=terraform output -raw alb_dns_name)/health

# 6. Tear down (avoid ongoing AWS costs)
make destroy
```

See [docs/runbook.md](docs/runbook.md) for a detailed step-by-step guide and troubleshooting.

### Testing

```bash
# Unit tests only — no Docker, no AWS needed
make test-unit

# Infrastructure tests (terraform validate + shellcheck) — no AWS needed
make test-infra

# Integration tests — starts Docker Compose automatically
make test-integration

# Full suite with log file
make test
# Log saved to logs/test-<timestamp>.log
```

**Test coverage:**

| Suite               | Tests | Requires               |
|---------------------|-------|------------------------|
| Unit — api-gateway  | 14    | Python deps only       |
| Unit — worker       | 7     | Python deps only       |
| Infrastructure      | 17    | terraform + shellcheck |
| Integration         | 12    | Docker Compose         |

See [docs/architecture.md](docs/architecture.md) for infrastructure diagrams and design decisions.

## Branch Strategy

```text
main          ← protected, deployable at all times
feat/<name>   ← new features
fix/<name>    ← bug fixes
ci/<name>     ← pipeline changes
chore/<name>  ← tooling, config, deps
```

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/).

---

*Built as a Cloud Engineer internship portfolio project.*
