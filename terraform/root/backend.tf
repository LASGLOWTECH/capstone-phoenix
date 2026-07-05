terraform {
  backend "s3" {
    bucket         = "taskapp-dev-terraform-state"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "taskapp-dev-terraform-lock"
  }
}
