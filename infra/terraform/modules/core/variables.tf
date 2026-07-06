variable "project_name" {
  description = "Project name prefix for the core module."
  type        = string
 
}

variable "environment" {
  description = "Deployment environment."
  type        = string

}

# variable "aws_region" {
#   description = "AWS region for resources created by the module."
#   type        = string
#   default     = "us-east-1"
# }
