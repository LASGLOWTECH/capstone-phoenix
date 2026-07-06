provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "Lasglowtech"
      CreatedBy   = "Terraform"
    }
  }

  retry_mode  = "standard"
  max_retries = 5
}
