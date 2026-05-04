# Internet-facing ALB distributes traffic across ECS tasks in both public subnets.
# Placing the ALB in multiple subnets (different AZs) is required by AWS
# and provides automatic failover if one AZ becomes unavailable.
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Project = var.project_name
  }
}

resource "aws_lb_target_group" "api_gateway" {
  name     = "${var.project_name}-tg-api"
  port     = var.api_gateway_port
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  # "ip" target type is required for Fargate (awsvpc network mode).
  # Unlike EC2 targets ("instance"), Fargate tasks register by their private IP.
  target_type = "ip"

  health_check {
    path = var.api_gateway_health_check_path

    # 2 consecutive successes to mark healthy — fast recovery after a restart.
    # 3 consecutive failures to mark unhealthy — avoids flapping on transient errors.
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }

  tags = {
    Project = var.project_name
  }
}

# HTTP-only listener — acceptable for a demo environment.
# For production: add an aws_lb_listener on port 443 with an ACM certificate
# and redirect port 80 → 443.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_gateway.arn
  }
}
