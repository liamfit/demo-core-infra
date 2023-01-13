data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name                 = "workload1-vpc"
  cidr                 = var.vpc_cidr
  enable_dns_hostnames = true

  azs             = [
    data.aws_availability_zones.available.names[0], 
    data.aws_availability_zones.available.names[1], 
    data.aws_availability_zones.available.names[2]
  ]

  private_subnets = [
    "${cidrsubnet(var.vpc_cidr,2,0)}", 
    "${cidrsubnet(var.vpc_cidr,2,1)}", 
    "${cidrsubnet(var.vpc_cidr,2,2)}"
  ]

  tags = {
    workload    = "workload1"
    environment = "dev"
  }
  private_subnet_tags = {
    type = "private"
  }
}

# ECR VPC endpoints
resource "aws_vpc_endpoint" "ecr-dkr-endpoint" {
  vpc_id              = module.vpc.vpc_id
  private_dns_enabled = true
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.vpc_endpoints_security_group.id]
  subnet_ids          = module.vpc.private_subnets
}
resource "aws_vpc_endpoint" "ecr-api-endpoint" {
  vpc_id              = module.vpc.vpc_id
  private_dns_enabled = true
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.vpc_endpoints_security_group.id]
  subnet_ids          = module.vpc.private_subnets
}

# Cloudwatch VPC endpoint
resource "aws_vpc_endpoint" "cloudwatch-vpc-endpoint" {
  vpc_id              = module.vpc.vpc_id
  private_dns_enabled = true
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.vpc_endpoints_security_group.id]
  subnet_ids          = module.vpc.private_subnets
}

# VPC interface endpoints security group
resource "aws_security_group" "vpc_endpoints_security_group" {
  description = "VPC endpoints Security Group"
  vpc_id      = module.vpc.vpc_id
}

# ECR VPC endpoint security group ingress from ECS
resource "aws_security_group_rule" "sg_ingress_rule_ecr_vpc_endpoint_from_ecs_cluster" {
  type                     = "ingress"
  description              = "Ingress from ECS cluster"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ecr_vpc_endpoint_security_group.id
  source_security_group_id = aws_security_group.ecs_security_group.id
}

# S3 Gateway endpoint
resource "aws_vpc_endpoint" "s3" {
  vpc_id          = module.vpc.vpc_id
  service_name    = "com.amazonaws.${var.aws_region}.s3"
  route_table_ids = module.vpc.private_route_table_ids
}

# Load balancer security group. CIDR and port ingress can be changed as required.
resource "aws_security_group" "lb_security_group" {
  description = "LoadBalancer Security Group"
  vpc_id      = module.vpc.vpc_id
}
resource "aws_security_group_rule" "sg_ingress_rule_all_to_lb" {
  type              = "ingress"
  description       = "Allow from anyone on port 80"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
  security_group_id = aws_security_group.lb_security_group.id
}

# Load balancer security group egress rule to ECS cluster security group.
resource "aws_security_group_rule" "sg_egress_rule_lb_to_ecs_cluster" {
  type                     = "egress"
  description              = "Target group egress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = aws_security_group.lb_security_group.id
  source_security_group_id = aws_security_group.ecs_security_group.id
}

# ECS cluster security group.
resource "aws_security_group" "ecs_security_group" {
  description = "ECS Security Group"
  vpc_id      = module.vpc.vpc_id
  egress {
    description = "Allow all outbound traffic by default"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    workload = "workload1"
  }
}

# ECS cluster security group ingress from the load balancer.
resource "aws_security_group_rule" "sg_ingress_rule_ecs_cluster_from_lb" {
  type                     = "ingress"
  description              = "Ingress from Load Balancer"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ecs_security_group.id
  source_security_group_id = aws_security_group.lb_security_group.id
}

# Create the internal application load balancer (ALB) in the private subnets.
resource "aws_lb" "ecs_alb" {
  load_balancer_type = "application"
  internal           = true
  subnets            = module.vpc.private_subnets
  security_groups    = [aws_security_group.lb_security_group.id]

  tags = {
    workload    = "workload1"
    environment = "dev"
  }
}

module "ecs" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "4.1.2"

  cluster_name = "ecs-fargate"

  fargate_capacity_providers = {
    FARGATE_SPOT = {
      default_capacity_provider_strategy = {
        weight = 100
      }
    }
  }

  tags = {
    environment = "dev"
    workload    = "workload1"
  }
}

# Create the VPC Link configured with the private subnets. Security groups are kept empty here, but can be configured as required.
resource "aws_apigatewayv2_vpc_link" "vpclink_apigw_to_alb" {
  name               = "vpclink_apigw_to_alb"
  security_group_ids = []
  subnet_ids         = module.vpc.private_subnets

  tags = {
    workload    = "workload1"
    environment = "dev"
  }
}

# Create the API Gateway HTTP endpoint
resource "aws_apigatewayv2_api" "apigw_http_endpoint" {
  name          = "serverlessland-pvt-endpoint"
  protocol_type = "HTTP"

  tags = {
    workload    = "workload1"
    environment = "dev"
  }
}

# # Create the API Gateway HTTP_PROXY integration between the created API and the private load balancer via the VPC Link.
# # Ensure that the 'DependsOn' attribute has the VPC Link dependency.
# # This is to ensure that the VPC Link is created successfully before the integration and the API GW routes are created.
# resource "aws_apigatewayv2_integration" "apigw_integration" {
#   api_id           = aws_apigatewayv2_api.apigw_http_endpoint.id
#   integration_type = "HTTP_PROXY"
#   integration_uri  = aws_lb_listener.ecs_alb_listener.arn

#   integration_method     = "ANY"
#   connection_type        = "VPC_LINK"
#   connection_id          = aws_apigatewayv2_vpc_link.vpclink_apigw_to_alb.id
#   payload_format_version = "1.0"
#   depends_on = [aws_apigatewayv2_vpc_link.vpclink_apigw_to_alb,
#     aws_apigatewayv2_api.apigw_http_endpoint,
#   aws_lb_listener.ecs_alb_listener]
# }

# # API GW route with ANY method
# resource "aws_apigatewayv2_route" "apigw_route" {
#   api_id     = aws_apigatewayv2_api.apigw_http_endpoint.id
#   route_key  = "ANY /{proxy+}"
#   target     = "integrations/${aws_apigatewayv2_integration.apigw_integration.id}"
#   depends_on = [aws_apigatewayv2_integration.apigw_integration]
# }

# Set a default stage
resource "aws_apigatewayv2_stage" "apigw_stage" {
  api_id      = aws_apigatewayv2_api.apigw_http_endpoint.id
  name        = "$default"
  auto_deploy = true
  depends_on  = [aws_apigatewayv2_api.apigw_http_endpoint]
}

# Generated API GW endpoint URL that can be used to access the application running on a private ECS Fargate cluster.
output "apigw_endpoint" {
  value       = aws_apigatewayv2_api.apigw_http_endpoint.api_endpoint
  description = "API Gateway Endpoint"
}
