terraform {
  required_version = ">= 1.11"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

# Cuenta de servicio propia de la app: solo lee sus dos secretos y usa el conector de Cloud SQL.
resource "google_service_account" "app" {
  project      = var.project_id
  account_id   = "sa-${var.name}"
  display_name = "Ledger ${var.name}"
}

resource "google_secret_manager_secret_iam_member" "reader" {
  for_each = var.secret_ids

  project   = var.project_id
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.app.email}"
}

resource "google_project_iam_member" "sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.app.email}"
}

# Los permisos de IAM tardan en propagarse; sin esta espera la primera revision puede fallar.
resource "time_sleep" "iam_propagation" {
  depends_on      = [google_secret_manager_secret_iam_member.reader, google_project_iam_member.sql_client]
  create_duration = var.iam_propagation_wait
}

resource "google_cloud_run_v2_service" "this" {
  #checkov:skip=CKV_GCP_126:La imagen se fija por digest (@sha256), que es mas estricto que una etiqueta
  name                = "ca-${var.name}"
  project             = var.project_id
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false
  labels              = var.labels
  depends_on          = [time_sleep.iam_propagation]

  template {
    service_account = google_service_account.app.email
    timeout         = "60s"

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [var.sql_connection_name]
      }
    }

    containers {
      image = var.image

      ports {
        container_port = 8000
      }

      resources {
        limits   = { cpu = "1", memory = "512Mi" }
        cpu_idle = true # CPU solo durante las solicitudes: con trafico cero no se cobra computo.
      }

      dynamic "env" {
        for_each = var.environment_variables
        content {
          name  = env.key
          value = env.value
        }
      }

      env {
        name = "DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = var.secret_ids["database-url"]
            version = "latest"
          }
        }
      }

      env {
        name = "JWT_SECRET"
        value_source {
          secret_key_ref {
            secret  = var.secret_ids["jwt-secret"]
            version = "latest"
          }
        }
      }

      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }

      liveness_probe {
        http_get {
          path = "/healthz"
        }
      }

      startup_probe {
        http_get {
          path = "/healthz"
        }
        period_seconds    = 5
        failure_threshold = 12
      }
    }
  }
}

# Aplicacion publica a proposito: la autenticacion la hace la propia app con JWT.
resource "google_cloud_run_v2_service_iam_member" "public" {
  #checkov:skip=CKV_GCP_102:La billetera es publica por diseno; las rutas /api exigen token JWT
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.this.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
