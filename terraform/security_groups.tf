# Rules are defined as separate aws_vpc_security_group_ingress/egress_rule resources
# instead of inline ingress/egress blocks \u2014 this is the HashiCorp best practice since
# provider v6. Separate resources have unique IDs, support tags, and avoid perpetual
# diffs caused by Terraform's attribute-as-blocks mode.

# ALB Security Group — allows HTTP from internet
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-sg-alb"
  description = "Allow HTTP inbound to ALB"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name    = "${var.project_name}-sg-alb"
    Project = var.project_name
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ECS Security Group — allows traffic from ALB only (api-gateway :8080, worker :9090)
resource "aws_security_group" "ecs" {
  name        = "${var.project_name}-sg-ecs"
  description = "Allow inbound from ALB to ECS tasks"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name    = "${var.project_name}-sg-ecs"
    Project = var.project_name
  }
}

resource "aws_vpc_security_group_ingress_rule" "ecs_from_alb_8080" {
  security_group_id            = aws_security_group.ecs.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = var.api_gateway_port
  to_port                      = var.api_gateway_port
  ip_protocol                  = "tcp"
}

# Port 9090 open within ECS SG for Prometheus scraping (Module 6)
resource "aws_vpc_security_group_ingress_rule" "ecs_prometheus_9090" {
  security_group_id            = aws_security_group.ecs.id
  referenced_security_group_id = aws_security_group.ecs.id
  from_port                    = var.worker_port
  to_port                      = var.worker_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "ecs_all" {
  security_group_id = aws_security_group.ecs.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
