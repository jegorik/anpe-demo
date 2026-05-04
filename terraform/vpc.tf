# Custom VPC instead of the AWS default VPC — demonstrates networking knowledge
# and avoids the risk of deploying into a shared/modified default VPC.
# All resources are isolated under this VPC.
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  # Both flags are required for ECS Fargate tasks to resolve AWS service
  # endpoints (ECR, CloudWatch) by hostname inside the VPC.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name    = "${var.project_name}-vpc"
    Project = var.project_name
  }
}

# One subnet per AZ using count — number of subnets equals length of
# var.public_subnet_cidrs, making it easy to scale to more AZs.
#
# ECS tasks are placed in PUBLIC subnets with assign_public_ip = true.
# This eliminates the need for a NAT Gateway (~$32/month savings) while
# still allowing tasks to pull images from ECR and write to CloudWatch.
resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  map_public_ip_on_launch = true

  tags = {
    Name    = "${var.project_name}-public-${count.index + 1}"
    Project = var.project_name
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name    = "${var.project_name}-igw"
    Project = var.project_name
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name    = "${var.project_name}-rt-public"
    Project = var.project_name
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
