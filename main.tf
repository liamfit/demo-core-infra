provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "workload1"
  cidr = var.vpc_cidr

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
    workload = "workload1"
    environment = "dev"
  }
}