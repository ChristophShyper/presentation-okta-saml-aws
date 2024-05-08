# PROVIDER AND BACKEND DEFINITION

# This file will be overwritten by Terragrunt
# Needed only for validation

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }

    okta = {
      source  = "okta/okta"
      version = "~> 4.0"
    }
  }
}
