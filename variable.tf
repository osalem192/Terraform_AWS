variable "region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnets" {
  default = {
    "us-east-1a" = 10
    "us-east-1b" = 20
  }
}

variable "private_subnets" {
  default = {
    "us-east-1a" = 100
    "us-east-1b" = 200
  }
}

variable "allowed_ports" {
  default = {
    "SSH"   = 22
    "HTTP"  = 80
    "HTTPS" = 443
  }
}

variable "ami_ec2" {
  default = "ami-0c614dee691cbbf37"
}
