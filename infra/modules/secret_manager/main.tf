terraform {
  required_version = ">= 1.11"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

resource "google_secret_manager_secret" "this" {
  #checkov:skip=CKV_GCP_82:Un secreto con rotacion exige un proceso de rotacion, fuera de alcance del laboratorio
  #checkov:skip=CKV2_GCP_18:Claves administradas por Google; CMEK exige Cloud KMS, que tiene costo
  for_each = nonsensitive(toset(keys(var.secrets)))

  project   = var.project_id
  secret_id = "${var.prefix}-${each.key}"
  labels    = var.labels

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "google_secret_manager_secret_version" "this" {
  for_each = nonsensitive(toset(keys(var.secrets)))

  secret      = google_secret_manager_secret.this[each.key].id
  secret_data = var.secrets[each.key]
}
