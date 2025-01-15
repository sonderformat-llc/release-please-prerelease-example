terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.46.0"
    }
  }
}

locals {
  client       = "tsc"
  project_name = "example-app"
  environment  = "test"
}

provider "aws" {
  region = "eu-west-1"

  default_tags {
    tags = {
      client      = local.client
      product     = local.project_name
      Environment = local.environment
    }
  }
}

module "service" {
  source = "../../modules/service"

  # x-release-please-start-version
  image_version = "1.5.0-beta.6"
  # x-release-please-end
}
