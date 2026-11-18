terraform {
  required_version = ">= 1.11"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # El bucket y el prefijo se pasan con -backend-config; ver .github/workflows/deploy-env.yml.
  backend "gcs" {}
}

# En GitHub Actions la identidad llega por Workload Identity Federation (credencial externa);
# en tu equipo, del token de gcloud.
provider "google" {
  project = var.project_id
  region  = var.region
}

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "image" {
  type = string
}

module "stack" {
  source = "../../modules/stack"

  environment   = "prod"
  project_id    = var.project_id
  region        = var.region
  image         = var.image
  max_instances = 3
  jwt_minutes   = 15
}

output "app_url" {
  value = module.stack.app_url
}

output "service_name" {
  value = module.stack.service_name
}

output "sql_instance" {
  value = module.stack.sql_instance
}
