variable "aws_region" {
  description = "AWS region for the infrastructure"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "vite-app-cluster-v2" # <--- Change this line
}

variable "ecr_repo_name" {
  description = "Name of the ECR repository"
  type        = string
  default     = "my-vite-app"
}