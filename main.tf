################################################################################
# Availability Zones list out
################################################################################
data "aws_availability_zones" "available" {
  state = "available"
}


provider "aws" {
    profile = "myaddwebtest"
    region = "us-east-2"
}
################################################################################
# MAIN VPC
################################################################################
resource "aws_vpc" "mainvpc" {    
    cidr_block           = "10.0.0.0/16"
    enable_dns_support   = true
    enable_dns_hostnames = true
    tags = { Name = "${var.name}-MAINVPC-${var.env}" }
}
##################
# Public subnets
##################
resource "aws_subnet" "public-subnet-a" {
    cidr_block = var.public-subnet-a
    vpc_id = aws_vpc.mainvpc.id
    availability_zone = data.aws_availability_zones.available.names[0]
    tags = { Name = "${var.name}-PUBLIC-SUBNET-A-${var.env}" }
}
resource "aws_subnet" "public-subnet-b" {
    cidr_block = var.public-subnet-b
    vpc_id = aws_vpc.mainvpc.id
    availability_zone = data.aws_availability_zones.available.names[1]
    tags = { Name = "${var.name}-PUBLIC-SUBNET-B-${var.env}" }
}
##################
# Private subnets
##################
resource "aws_subnet" "private-subnet-a" {
    cidr_block = var.private_subnet-a
    vpc_id = aws_vpc.mainvpc.id
    availability_zone = data.aws_availability_zones.available.names[0]
    tags = { Name = "${var.name}-PRIVATE-SUBNET-A-${var.env}" }
}
resource "aws_subnet" "private-subnet-b" {
    cidr_block = var.private_subnet-b
    vpc_id = aws_vpc.mainvpc.id
    availability_zone = data.aws_availability_zones.available.names[1]
    tags = { Name = "${var.name}-PRIVATE-SUBNET-B-${var.env}" }
}
##################
# Route Tables For The Subnets
##################
resource "aws_route_table" "public-route-table" {
  vpc_id = aws_vpc.mainvpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${var.name}-PUBLIC-ROUTE-TABLE-${var.env}" }
}
resource "aws_route_table" "private-route-table" {
  vpc_id = aws_vpc.mainvpc.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "${var.name}-PRIVATE-ROUTE-TABLE-${var.env}" }
}
##################
# Associate the newly created route tables to the subnets
##################
resource "aws_route_table_association" "public-route-asso-a" {
  route_table_id = aws_route_table.public-route-table.id
  subnet_id = aws_subnet.public-subnet-a.id
}
resource "aws_route_table_association" "public-route-asso-b" {
  route_table_id = aws_route_table.public-route-table.id
  subnet_id = aws_subnet.public-subnet-b.id
}
resource "aws_route_table_association" "private-route-asso-a" {
  route_table_id = aws_route_table.private-route-table.id
  subnet_id = aws_subnet.private-subnet-a.id
}
resource "aws_route_table_association" "private-route-asso-b" {
  route_table_id = aws_route_table.private-route-table.id
  subnet_id = aws_subnet.private-subnet-b.id
}

##################
# Internet Gateway for the public subnet
##################
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.mainvpc.id
  tags = { Name = "${var.name}-IGW-${var.env}" }
}

##################
# NAT gateway
##################
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.eip.id
  subnet_id = aws_subnet.public-subnet-a.id
  depends_on = [ aws_eip.eip ]
  tags = { Name = "${var.name}-NAT-${var.env}" }
}

##################
# Elastic IP
##################
resource "aws_eip" "eip" {
  vpc = true
  associate_with_private_ip = "10.0.0.10"
  depends_on = [ aws_internet_gateway.igw ]
  tags = { Name = "${var.name}-EIP-${var.env}" }
}
################################################################################
# Security Groups
################################################################################
##################
# Traffic Internet ALB
##################
resource "aws_security_group" "sg-lb" {
    name = "sg_lb"
    description = "SG for ALB"
    vpc_id = aws_vpc.mainvpc.id

    ingress {
        description = "HTTP"
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    egress {
        from_port = 0
        to_port = 0
        protocol = -1
        cidr_blocks = ["0.0.0.0/0"]
    }

}
##################
# ECS Security group (traffic ALB -> ECS, ssh -> ECS)
##################
resource "aws_security_group" "sg-ecs" {
  name        = "sg_ecs"
  description = "Allows inbound access from the ALB only"
  vpc_id      = aws_vpc.mainvpc.id

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = -1
    security_groups = [aws_security_group.sg-lb.id]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}
##################
#RDS Security Group (traffic ECS -> RDS)
##################
resource "aws_security_group" "sg-rds" {
  name        = "sg_rds"
  description = "Allows inbound access from ECS only"
  vpc_id      = aws_vpc.mainvpc.id

  ingress {
    protocol        = "tcp"
    from_port       = "3306"
    to_port         = "3306"
    security_groups = [aws_security_group.sg-ecs.id]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

################################################################################
# ALB
################################################################################
# Production Load Balancer
resource "aws_lb" "ecs-lab-alb" {
  name               = "${var.ecs_cluster_name}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.sg-lb.id]
  subnets            = [aws_subnet.public-subnet-a.id,aws_subnet.public-subnet-b.id]
}

# Target group client
resource "aws_alb_target_group" "default-target-group" {
  name     = "${var.ecs_cluster_name}-tg"
  port     = 80
  protocol = "HTTP"
  target_type = "ip"
  vpc_id   = aws_vpc.mainvpc.id

  health_check {
    healthy_threshold   = 5
    unhealthy_threshold = 2
    timeout             = 2
    interval            = 5
    matcher             = "200,302,301"
    path                = "/"
    protocol            = "HTTP" 
  }
}

# Listener (redirects traffic from the load balancer to the target group)
resource "aws_alb_listener" "alb-listener" {
  load_balancer_arn = aws_lb.ecs-lab-alb.arn
  port              = "80"
  protocol          = "HTTP"
  depends_on        = [aws_alb_target_group.default-target-group]

  default_action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.default-target-group.arn
  }
}


################################################################################
# ECS 
################################################################################
resource "aws_ecs_cluster" "mtncluster" {
  name = "${var.ecs_cluster_name}-LAB"
   setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

#============================ task Defination and nginx service service

resource "aws_ecs_task_definition" "nginxweb" {
  family = "nginx-family"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  task_role_arn            = "arn:aws:iam::249588176497:role/ecsTaskExecutionRole"
  container_definitions = jsonencode([{
   name        = "nginxcon"
   image       = "nginx:latest"
   essential   = true
   portMappings = [{
     protocol      = "tcp"
     containerPort = 80
     hostPort      = 80
   }]
  }])
}

resource "aws_ecs_service" "main" {
 name                               = "nginxsvc"
 cluster                            = aws_ecs_cluster.mtncluster.id
 task_definition                    = aws_ecs_task_definition.nginxweb.arn
 desired_count                      = 2
 deployment_minimum_healthy_percent = 50
 deployment_maximum_percent         = 200
 launch_type                        = "FARGATE"
 scheduling_strategy                = "REPLICA"
 
 network_configuration {
   security_groups  = [aws_security_group.sg-ecs.id]
   subnets          = [aws_subnet.private-subnet-a.id,aws_subnet.private-subnet-b.id]
   assign_public_ip = false
 }
 
 load_balancer {
   target_group_arn = aws_alb_target_group.default-target-group.arn
   container_name   = "nginxcon"
   container_port   = 80
 }
  # depends_on = [aws_lb_listener.ELB-listener]
} 


#=================================================  Auto Scaling
# ============================  Autoscaling Targate
resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = 4
  min_capacity       = 2
  resource_id        = "service/${aws_ecs_cluster.mtncluster.name}/${aws_ecs_service.main.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# ============================  Policy Attache
resource "aws_appautoscaling_policy" "ecs_policy_memory" {
  name               = "memory-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace
 
  target_tracking_scaling_policy_configuration {
   predefined_metric_specification {
     predefined_metric_type = "ECSServiceAverageMemoryUtilization"
   }
   target_value       = 80
  }
}


resource "aws_appautoscaling_policy" "ecs_policy_cpu" {
  name               = "cpu-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace
 
  target_tracking_scaling_policy_configuration {
   predefined_metric_specification {
     predefined_metric_type = "ECSServiceAverageCPUUtilization"
   }
   target_value       = 60
  }
}










################################################################################
# I AM  Role
################################################################################
# resource "aws_iam_role" "ecs-host-role" {
#   name               = "ecs_host_role_prod"
#   assume_role_policy = file("policies/ecs-role.json")
# }

# resource "aws_iam_role_policy" "ecs-instance-role-policy" {
#   name   = "ecs_instance_role_policy"
#   policy = file("policies/ecs-instance-role-policy.json")
#   role   = aws_iam_role.ecs-host-role.id
# }
# resource "aws_iam_role" "ecs-service-role" {
#   name               = "ecs_service_role_prod"
#   assume_role_policy = file("policies/ecs-role.json")
# }

# resource "aws_iam_role_policy" "ecs-service-role-policy" {
#   name   = "ecs_service_role_policy"
#   policy = file("policies/ecs-service-role-policy.json")
#   role   = aws_iam_role.ecs-service-role.id
# }

# resource "aws_iam_instance_profile" "ecs" {
#   name = "ecs_instance_profile_prod"
#   path = "/"
#   role = aws_iam_role.ecs-host-role.name
# }