# Trust policy: only the ECS Tasks service can assume this role.
# Scoping to ecs-tasks.amazonaws.com (not ecs.amazonaws.com) follows
# least-privilege — the role is for task execution, not cluster management.
data "aws_iam_policy_document" "ecs_task_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name               = "${var.project_name}-ecs-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json

  tags = {
    Project = var.project_name
  }
}

# AWS-managed policy that grants exactly what ECS needs for task startup:
#   - ecr:GetAuthorizationToken, ecr:BatchGetImage — pull images from ECR
#   - logs:CreateLogStream, logs:PutLogEvents    — write to CloudWatch Logs
# Note: logs:CreateLogGroup is NOT included — added separately below.
resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# logs:CreateLogGroup is required when awslogs-create-group = "true" in the
# container log configuration. It is intentionally omitted from the AWS managed
# policy above, so we add it as a scoped inline policy restricted to this
# project's log group prefix only (least-privilege).
resource "aws_iam_role_policy" "ecs_task_execution_logs" {
  name = "${var.project_name}-ecs-logs-create"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup"]
      Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/${var.project_name}/*"
    }]
  })
}
