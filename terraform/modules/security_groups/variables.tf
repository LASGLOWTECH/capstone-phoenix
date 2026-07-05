variable "project_name" {
  description = "Project name prefix for the security groups module."
  type        = string
}

variable "environment" {
  description = "Deployment environment for tags."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where security groups should be created."
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed for SSH access."
  type        = list(string)
  default     =   ["0.0.0.0/0 "]
}