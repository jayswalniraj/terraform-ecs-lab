output "load_balancer_ip" {
  value = aws_lb.ecs-lab-alb.dns_name
}