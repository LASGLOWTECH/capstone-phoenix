
variable "project_name" {
  description = "Project prefix used for backend resources."
  type        = string
  default     = "taskapp-dev"
}



variable "aws_region" {
  description = "AWS region to create backend resources in."
  type        = string
  default     = "us-east-1"

}





variable "environment" {
  description = "Deployment environment tag."
  type        = string
  default     = "dev"
}

# variable "kms_key_id" {
#   description = "KMS Key ID or ARN for S3 encryption. Leave empty to use AWS-managed keys."
#   type        = string
#   default     = ""
# }
