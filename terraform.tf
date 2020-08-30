terraform {
  backend "s3" {
    region  = "me-south-1"
    encrypt = true
  }
}
