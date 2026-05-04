# Container Insights enables CloudWatch metrics (CPU, memory, network) per task.
# Adds minor cost (~$0.50/GB of metrics) but provides visibility essential
# for debugging and is expected in any production-grade setup.
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  tags = {
    Project = var.project_name
  }
}

# FARGATE launch type: serverless containers — no EC2 instances to provision,
# patch, or scale. AWS manages the underlying infrastructure.
#
# awsvpc network mode: each task gets its own ENI with a private IP.
# Required for Fargate and enables per-task security group assignment.
resource "aws_ecs_task_definition" "api_gateway" {
  family                   = "${var.project_name}-api-gateway"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.api_gateway_cpu
  memory                   = var.api_gateway_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([{
    name = "api-gateway"
    # Falls back to ECR repo URL + :latest when var.api_gateway_image is not set.
    # Set the variable in terraform.tfvars to pin a specific image digest.
    image = var.api_gateway_image != "" ? var.api_gateway_image : "${aws_ecr_repository.api_gateway.repository_url}:latest"

    portMappings = [{
      containerPort = var.api_gateway_port
      protocol      = "tcp"
    }]

    # Health check uses Python stdlib (urllib) — avoids needing curl/wget
    # in a minimal Python base image. startPeriod=10s gives FastAPI time
    # to initialise before the first check fires.
    healthCheck = {
      command     = ["CMD-SHELL", "python -c \"import urllib.request; urllib.request.urlopen('http://localhost:${var.api_gateway_port}${var.api_gateway_health_check_path}')\" || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 10
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/${var.project_name}/api-gateway"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
        # Automatically creates the CloudWatch log group on first task start.
        # Removes the need to pre-create log groups via aws_cloudwatch_log_group.
        "awslogs-create-group" = "true"
      }
    }
  }])

  tags = {
    Project = var.project_name
  }
}

resource "aws_ecs_task_definition" "worker" {
  family                   = "${var.project_name}-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.worker_cpu
  memory                   = var.worker_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([{
    name  = "worker"
    image = var.worker_image != "" ? var.worker_image : "${aws_ecr_repository.worker.repository_url}:latest"

    portMappings = [{
      containerPort = var.worker_port
      protocol      = "tcp"
    }]

    # Worker exposes /metrics (Prometheus format) on :9090 instead of /health.
    # This endpoint serves as both the health check and the Prometheus scrape target.
    healthCheck = {
      command     = ["CMD-SHELL", "python -c \"import urllib.request; urllib.request.urlopen('http://localhost:${var.worker_port}${var.worker_health_check_path}')\" || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 10
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/${var.project_name}/worker"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
        "awslogs-create-group"  = "true"
      }
    }
  }])

  tags = {
    Project = var.project_name
  }
}

resource "aws_ecs_service" "api_gateway" {
  name            = "${var.project_name}-api-gateway"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api_gateway.arn
  desired_count   = var.api_gateway_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = aws_subnet.public[*].id
    security_groups = [aws_security_group.ecs.id]

    # Public IP allows the task to reach ECR (image pull) and CloudWatch (logs)
    # without a NAT Gateway. Safe because the ECS security group only allows
    # inbound traffic from the ALB security group — not from the internet directly.
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api_gateway.arn
    container_name   = "api-gateway"
    container_port   = var.api_gateway_port
  }

  # Ensures the ALB listener exists before the service tries to register targets.
  # Without this, the service creation can race ahead of the listener and fail.
  depends_on = [aws_lb_listener.http]

  tags = {
    Project = var.project_name
  }
}

# Worker is an internal service — no ALB attachment.
# It is reachable within the VPC on port 9090 via its private IP
# (visible via ECS service discovery or aws ecs describe-tasks).
# The ecs_prometheus_9090 SG rule allows Prometheus to scrape it in Module 6.
resource "aws_ecs_service" "worker" {
  name            = "${var.project_name}-worker"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count   = var.worker_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  tags = {
    Project = var.project_name
  }
}
