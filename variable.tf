############### 
# TAG Creation
############### 
variable "name" {
  description = "the name of your stack, e.g. \"demo\""
  default = "INIC-ECS-LAB"
}
variable "env" {
  description = "The name Of  Environment"
  default = "STAGING"
}

############### 
# VPC and Component
############### 
variable "public-subnet-a" {
  description = "CIDR Block for Public Subnet A"
  default     = "10.0.11.0/24"
}
variable "public-subnet-b" {
  description = "CIDR Block for Public Subnet B"
  default     = "10.0.12.0/24"
}
variable "private_subnet-a" {
  description = "CIDR Block for Private Subnet A"
  default     = "10.0.21.0/24"
}
variable "private_subnet-b" {
  description = "CIDR Block for Private Subnet B"
  default     = "10.0.22.0/24"
}
############### 
#  ALB
############### 
variable "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  default     = "LAB-CLUSTER"
}