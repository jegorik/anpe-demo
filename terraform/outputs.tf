output "ecr_api_gateway_uri" {
  description = "ECR repository URI for api-gateway"
  value       = aws_ecr_repository.api_gateway.repository_url
}

output "ecr_worker_uri" {
  description = "ECR repository URI for worker"
  value       = aws_ecr_repository.worker.repository_url
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "aws_account_id" {
  description = "AWS Account ID (retrieved dynamically)"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS region used for deployment"
  value       = var.aws_region
}
