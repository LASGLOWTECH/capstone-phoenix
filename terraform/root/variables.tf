
variable "project_name" {
  description = "Project prefix used for the cluster."
  type        = string
  default     = "taskapp"
}

variable "environment" {
  description = "Deployment environment tag."
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region to deploy resources into."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.10.0.0/16"
}

variable "instance_type" {
  description = "EC2 instance type for the k3s nodes."
  type        = string
  default     = "t3.small"
}

variable "ami_id" {
  description = "Optional AMI ID for Ubuntu 22.04 in the selected region. If omitted, Terraform will resolve the latest Canonical Ubuntu 22.04 AMI automatically."
  type        = string
  default     = null

  validation {
    condition     = var.ami_id == null || trimspace(var.ami_id) == "" || can(regex("^ami-[a-z0-9]+$", var.ami_id))
    error_message = "ami_id must be null, empty, or a valid EC2 AMI ID such as ami-0123456789abcdef0."
  }
}

variable "key_name" {
  description = "SSH key pair name for the nodes."
  type        = string
}

variable "allowed_ssh_cidr" {
  
  description = "CIDR blocks allowed to reach SSH and Kubernetes API."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
variable "db_password" {
  description = "Master password for the RDS database."
  type        = string
  sensitive   = true
}