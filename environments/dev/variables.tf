variable "aws_region" {
  type    = string
  default = ""
}

variable "vpc_cidr" {
  type    = string
  default =  "10.0.0.0/16"
}

variable "tags" {
  type    = map(any)
  default = {
    "project"     = "demo",
    "environment" = "dev"
  }
}

variable "alb_port" {
  type    = number
  default = 80
}

variable "container_port" {
  type    = number
  default = 8080
}