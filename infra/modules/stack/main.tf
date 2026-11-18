terraform {
  required_version = ">= 1.11"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

locals {
  name = "ledger-${var.environment}"
  labels = {
    project     = "eci-ledger-lab"
    environment = var.environment
    managed_by  = "terraform"
  }
  # Solo prod tiene copias de seguridad y metrica de errores: dev debe poder borrarse sin residuos.
  is_prod = var.environment == "prod"
}

# El nombre de una instancia de Cloud SQL eliminada no se puede reutilizar durante una semana.
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "random_password" "jwt" {
  length  = 64
  special = false
}

module "database" {
  source = "../database"

  instance_name   = "sql-${local.name}-${random_string.suffix.result}"
  project_id      = var.project_id
  region          = var.region
  backups_enabled = local.is_prod
  labels          = local.labels
}

module "secrets" {
  source = "../secret_manager"

  project_id = var.project_id
  region     = var.region
  prefix     = local.name
  labels     = local.labels

  secrets = {
    "database-url" = module.database.database_url
    "jwt-secret"   = random_password.jwt.result
  }
}

module "app" {
  source = "../cloud_run"

  name                 = local.name
  project_id           = var.project_id
  region               = var.region
  image                = var.image
  sql_connection_name  = module.database.connection_name
  secret_ids           = module.secrets.secret_ids
  max_instances        = var.max_instances
  iam_propagation_wait = var.iam_propagation_wait
  labels               = local.labels

  environment_variables = {
    APP_ENV     = var.environment
    JWT_MINUTES = tostring(var.jwt_minutes)
  }
}

# Solo prod: metrica de respuestas 5xx, base para alertas. La retencion de logs de Cloud Run es gratuita.
resource "google_logging_metric" "errors" {
  count = local.is_prod ? 1 : 0

  project = var.project_id
  name    = "${local.name}-errores-5xx"
  filter  = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${module.app.service_name}\" AND httpRequest.status>=500"

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}
