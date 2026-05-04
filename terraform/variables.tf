variable "project_name" {
  description = "Project name used as prefix for all AWS resources"
  type        = string
  default     = "anpe"
}

variable "aws_region" {
  description = "AWS region to deploy resources into"
  type        = string
  default     = "eu-central-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

# Default is empty string — ecs.tf falls back to ECR repo URL + :latest when not set.
# Populate this in terraform.tfvars after running scripts/build-push.sh
# to pin a specific image digest for reproducible deployments.
variable "api_gateway_image" {
  description = "Full ECR image URI for api-gateway (set after build-push)"
  type        = string
  default     = ""
}

variable "worker_image" {
  description = "Full ECR image URI for worker (set after build-push)"
  type        = string
  default     = ""
}

# Fargate CPU/memory must be a valid combination — see AWS docs:
# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-cpu-memory-error.html
# 256 CPU / 512 MiB is the smallest valid Fargate task size.
# Sufficient for a lightweight FastAPI service under demo load.
variable "api_gateway_cpu" {
  description = "CPU units for api-gateway task (1 vCPU = 1024)"
  type        = number
  default     = 256
}

variable "api_gateway_memory" {
  description = "Memory (MiB) for api-gateway task"
  type        = number
  default     = 512
}

variable "worker_cpu" {
  description = "CPU units for worker task"
  type        = number
  default     = 256
}

variable "worker_memory" {
  description = "Memory (MiB) for worker task"
  type        = number
  default     = 512
}

# ---------------------------------------------------------------------------
# Networking / Ports
# ---------------------------------------------------------------------------

variable "api_gateway_port" {
  description = "Container port exposed by the api-gateway service"
  type        = number
  default     = 8080
}

variable "worker_port" {
  description = "Container port exposed by the worker service (also the Prometheus metrics endpoint)"
  type        = number
  default     = 9090
}

# ---------------------------------------------------------------------------
# Health checks
# ---------------------------------------------------------------------------

variable "api_gateway_health_check_path" {
  description = "HTTP path used by the ALB target group health check for api-gateway"
  type        = string
  default     = "/health"
}

variable "worker_health_check_path" {
  description = "HTTP path used by the ECS container health check for the worker"
  type        = string
  default     = "/metrics"
}

# ---------------------------------------------------------------------------
# ECS scaling
# ---------------------------------------------------------------------------

variable "api_gateway_desired_count" {
  description = "Number of api-gateway ECS tasks to keep running"
  type        = number
  default     = 1
}

variable "worker_desired_count" {
  description = "Number of worker ECS tasks to keep running"
  type        = number
  default     = 1
}

# ---------------------------------------------------------------------------
# ECS observability
# ---------------------------------------------------------------------------

# Disabling saves ~$0.50/GB of metrics but removes CPU/memory graphs in the
# ECS console. Recommended to keep enabled for any non-trivial workload.
variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights metrics for the ECS cluster"
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# ECR repository settings
# ---------------------------------------------------------------------------

# MUTABLE — suitable for dev/demo (overwrites :latest on each push).
# IMMUTABLE — enforces image provenance; recommended for production.
variable "ecr_image_tag_mutability" {
  description = "ECR image tag mutability: MUTABLE (overwrite tags) or IMMUTABLE (enforce provenance)"
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.ecr_image_tag_mutability)
    error_message = "ecr_image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "ecr_scan_on_push" {
  description = "Trigger an AWS Inspector vulnerability scan on every image push"
  type        = bool
  default     = true
}

variable "ecr_image_retention_count" {
  description = "Number of images to retain per ECR repository (older images are expired)"
  type        = number
  default     = 5
}
