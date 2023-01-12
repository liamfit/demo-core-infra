terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.47.0"
    }
  }

  backend "s3" {
    encrypt        = true
    dynamodb_table = "terraform-state"
  }
}

provider "aws" {
  region = var.aws_region
}
