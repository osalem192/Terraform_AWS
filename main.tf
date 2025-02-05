# >>>>>>>>>>>>>>>>>>>>  Provider    <<<<<<<<<<<<<<<<<<<<<<<<<

provider "aws" {
  region = var.region
}

# >>>>>>>>>>>>>>>>>>>>  VPC & Subnets   <<<<<<<<<<<<<<<<<<<<<<<<<

resource "aws_vpc" "custom" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "Custom_CapProject_VPC"
  }
}

resource "aws_subnet" "public_subnets" {
  for_each                = var.public_subnets
  vpc_id                  = aws_vpc.custom.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, each.value)
  availability_zone       = each.key
  map_public_ip_on_launch = true
  tags = {
    Name = "${each.key}_Public_Subnet"
  }
}

resource "aws_subnet" "private_subnets" {
  for_each          = var.private_subnets
  vpc_id            = aws_vpc.custom.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, each.value)
  availability_zone = each.key
  tags = {
    Name = "${each.key}_Private_Subnet"
  }
}

# >>>>>>>>>>>>>>> Route table & IGW & NGW   <<<<<<<<<<<<<<<<<<<<<

resource "aws_route_table" "public" {
  depends_on = [aws_internet_gateway.CP_IGW]
  vpc_id     = aws_vpc.custom.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.CP_IGW.id
  }
  tags = {
    "name" = "publicRT"
  }
}

resource "aws_route_table" "private" {
  depends_on = [aws_internet_gateway.CP_IGW]
  vpc_id     = aws_vpc.custom.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.NGW.id
  }
  tags = {
    "name" = "privateRT"
  }
}

resource "aws_internet_gateway" "CP_IGW" {
  vpc_id = aws_vpc.custom.id
  tags = {
    Name = "CP_IGW"
  }
}

resource "aws_route_table_association" "public_assoc" {
  route_table_id = aws_route_table.public.id
  for_each       = aws_subnet.public_subnets
  subnet_id      = each.value.id
}

resource "aws_route_table_association" "private_assoc" {
  route_table_id = aws_route_table.private.id
  for_each       = aws_subnet.private_subnets
  subnet_id      = each.value.id
}

resource "aws_eip" "eip" {
  depends_on = [aws_internet_gateway.CP_IGW]
  domain     = "vpc"
  tags = {
    "name" = "EIP_IGW"
  }
}

resource "aws_nat_gateway" "NGW" {
  allocation_id = aws_eip.eip.id
  # for_each      = aws_subnet.public_subnets
  # subnet_id     = each.value.id
  subnet_id = aws_subnet.public_subnets["us-east-1a"].id

  tags = {
    Name = "gwNAT"
  }
  # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
  depends_on = [aws_internet_gateway.CP_IGW]
}

#>>>>>>>>>>>>>>>>>>>>>  Security Groups and Target Groups<<<<<<<<<<<<<<<<<<<<

resource "aws_security_group" "webSG" {
  vpc_id = aws_vpc.custom.id
  tags = {
    Name = "webSG"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allowed_web_in_ports" {
  for_each          = var.allowed_ports
  security_group_id = aws_security_group.webSG.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = each.value
  ip_protocol       = "tcp"
  to_port           = each.value
  tags = {
    "name" = "${each.key}_port_ingress"
  }
}

resource "aws_vpc_security_group_egress_rule" "allowed_web_eg_ports" {
  for_each          = var.allowed_ports
  security_group_id = aws_security_group.webSG.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = each.value
  ip_protocol       = "tcp"
  to_port           = each.value
  tags = {
    "name" = "${each.key}_port_egress"
  }
}

resource "aws_security_group" "ALBSG" {
  vpc_id = aws_vpc.custom.id
  tags = {
    Name = "ALBSG"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allowed_albsg_in_ports" {
  security_group_id = aws_security_group.ALBSG.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
  tags = {
    "name" = "HTTP_port_ingress"
  }
}
resource "aws_vpc_security_group_egress_rule" "allowed_albsg_eg_ports" {
  security_group_id = aws_security_group.ALBSG.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
  tags = {
    "name" = "HTTP_port_egress"
  }
}



# >>>>>>>>>>>>>>>>>>>>>>>>    ALB   <<<<<<<<<<<<<<<<<<<<<<<<

resource "aws_lb" "alb" {
  depends_on         = [aws_vpc.custom]
  name               = "alb-cp"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ALBSG.id]
  subnets            = [aws_subnet.public_subnets["us-east-1a"].id, aws_subnet.public_subnets["us-east-1b"].id]
}

resource "aws_lb_target_group" "alb-tg" {
  depends_on = [aws_instance.web]
  name       = "alb-TG"
  port       = 80
  protocol   = "HTTP"
  vpc_id     = aws_vpc.custom.id
  tags = {
    "name" = "ALB_TG"
  }
}

resource "aws_lb_target_group_attachment" "alb_tg_attach" {
  depends_on       = [aws_instance.web]
  target_group_arn = aws_lb_target_group.alb-tg.arn
  for_each         = aws_instance.web
  target_id        = each.value.id
  port             = 80
}

resource "aws_lb_listener" "alb_listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb-tg.arn
  }
}

# >>>>>>>>>>>>>>>>>>>>  Auto_Scaling group    <<<<<<<<<<<<<<<<<<<<<<<<<

resource "aws_launch_template" "scaled_instance" {
  name_prefix            = "scaled-instance"
  image_id               = var.ami_ec2
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.webSG.id] # ✅ Corrected

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "ScaledInstance"
    }
  }
}

resource "aws_autoscaling_group" "ec2_auto_scaling" {
  min_size         = 1
  max_size         = 3
  desired_capacity = 1
  vpc_zone_identifier = [
    aws_subnet.private_subnets["us-east-1a"].id,
    aws_subnet.private_subnets["us-east-1b"].id
  ]

  launch_template { # ✅ Only use `launch_template`
    id      = aws_launch_template.scaled_instance.id
    version = "$Latest"
  }
}

resource "aws_autoscaling_attachment" "asg_target" {
  autoscaling_group_name = aws_autoscaling_group.ec2_auto_scaling.id
  lb_target_group_arn    = aws_lb_target_group.alb-tg.arn
}

# >>>>>>>>>>>>>>>>>>>>  EC2_EBS    <<<<<<<<<<<<<<<<<<<<<<<<<

resource "aws_instance" "web" {
  ami             = var.ami_ec2
  instance_type   = "t2.micro"
  security_groups = [aws_security_group.webSG.id]
  for_each        = aws_subnet.public_subnets
  subnet_id       = each.value.id
  user_data       = file("./${each.key}.sh")

  root_block_device {
    encrypted = true
  }
  tags = {
    Name = "EBS_Public_${each.key}"
  }
}

resource "aws_instance" "app" {
  ami             = var.ami_ec2
  instance_type   = "t2.micro"
  security_groups = [aws_security_group.webSG.id]
  for_each        = aws_subnet.private_subnets
  subnet_id       = each.value.id
  root_block_device {
    encrypted = true
  }
  tags = {
    Name = "EBS_Private_${each.key}"
  }
}
