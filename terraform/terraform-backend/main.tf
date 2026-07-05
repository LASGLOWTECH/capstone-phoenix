provider "aws" {
  region = var.aws_region
}

//S3 bucket for storing terraform states

resource "aws_s3_bucket" "terraform_state" {
  bucket = "${var.project_name}-terraform-state"

  tags = {
    Name        = "${var.project_name}-terraform-state"
    Environment = var.environment
  }
}

# enable versioning for the S3 bucket to keep track of state file changes
# this is to ensure we can recover previous states if needed
resource "aws_s3_bucket_versioning" "terraform_state_versioning" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# enable server-side encryption for the S3 bucket to ensure state files are encrypted at rest
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state_encryption" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
      # kms_master_key_id = var.kms_key_id
    }
  }
}

# create a DynamoDB table for state locking to prevent concurrent modifications of the state file
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "${var.project_name}-terraform-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name        = "${var.project_name}-terraform-lock"
    Environment = var.environment
  }
}
