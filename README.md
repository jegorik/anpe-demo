# ANPE Demo — Automated Network Processing Engine

A cloud-native microservices demo platform built to practise real-world Cloud Engineering skills:
Docker · GitHub Actions CI/CD · Kubernetes (k3s) · Prometheus · Grafana · AWS.

> **Purpose:** Internship preparation for a Cloud Engineer role focused on microservices,
> DevOps automation, and distributed systems.

---

## Architecture

```text
┌─────────────────┐     HTTP/REST      ┌──────────────────┐
│   api-gateway   │ ──── task req ────▶ │     worker       │
│                 │                     │                  │
│  - REST API     │ ◀─── status ─────── │  - task runner   │
│  - validation   │                     │  - status update │
│  - /metrics     │                     │  - /metrics      │
└────────┬────────┘                     └────────┬─────────┘
         │                                       │
         └──────────────┬────────────────────────┘
                        │
               ┌────────▼────────┐
               │   task-store    │
               │ queued→running  │
               │  →done/failed   │
               └─────────────────┘
                        │
               ┌────────▼────────┐
               │   Prometheus    │──▶  Grafana dashboards
               └─────────────────┘
```

## Tech Stack

| Layer          | Tool                                  |
|----------------|---------------------------------------|
| Containers     | Docker 29, Docker Compose             |
| CI/CD          | GitHub Actions                        |
| Orchestration  | k3s v1.31 (self-hosted on Proxmox)    |
| Packaging      | Helm                                  |
| Observability  | Prometheus + Grafana                  |
| Cloud          | AWS ECR + ECS Fargate                 |
| Source control | Git + GitHub                          |

## Learning Roadmap

- [x] Module 1 — Git workflow & project structure
- [ ] Module 2 — Docker: Dockerfile, multi-stage builds, Compose
- [ ] Module 3 — CI/CD: GitHub Actions (build → test → push to GHCR)
- [ ] Module 4 — Kubernetes: deploy to k3s with Helm
- [ ] Module 5 — CD: auto-deploy from GitHub Actions to k3s (self-hosted runner)
- [ ] Module 6 — Observability: Prometheus scraping + Grafana dashboards
- [ ] Module 7 — AWS: ECR image registry + ECS Fargate deployment

## Repository Structure

```text
anpe-demo/
├── .github/
│   ├── copilot-instructions.md   # AI agent context and rules
│   └── workflows/                # GitHub Actions pipelines
├── services/
│   ├── api-gateway/              # REST API service
│   └── worker/                   # Task processing service
├── helm/                         # Helm chart (added in Module 4)
├── monitoring/                   # Prometheus + Grafana configs (Module 6)
└── docs/                         # Architecture decisions and runbooks
```

## Getting Started

```bash
# Clone the repo
git clone https://github.com/jegorik/anpe-demo.git
cd anpe-demo

# Run locally with Docker Compose (available after Module 2)
docker compose up --build
```

## Contributing / Branch Strategy

This project uses trunk-based development with short-lived feature branches.

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
