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
  }
}

resource "random_password" "admin" {
  length  = 32
  special = false
}

resource "google_sql_database_instance" "this" {
  #checkov:skip=CKV_GCP_60:Sin VPC de pago la instancia conserva IP publica, pero sin redes autorizadas: solo entra el conector de Cloud Run
  #checkov:skip=CKV_GCP_79:PostgreSQL 15 es una version soportada; la 16 queda como mejora
  #checkov:skip=CKV2_GCP_13:La auditoria de sentencias (pgaudit) genera logs con costo; extension opcional
  #checkov:skip=CKV_GCP_109:log_min_messages ya esta en error; el control exige ademas log_min_error_statement, innecesario aqui
  #checkov:skip=CKV_GCP_110:pgAudit genera logs con costo; extension opcional
  #checkov:skip=CKV_GCP_6:Se usa ssl_mode = ENCRYPTED_ONLY, que reemplaza al atributo obsoleto require_ssl
  name                = var.instance_name
  project             = var.project_id
  region              = var.region
  database_version    = "POSTGRES_15"
  deletion_protection = false # El laboratorio debe poder destruirse; en produccion real seria true.

  settings {
    tier              = var.tier
    edition           = "ENTERPRISE"
    availability_type = "ZONAL"
    disk_size         = 10
    disk_type         = "PD_HDD"
    disk_autoresize   = false
    user_labels       = var.labels

    ip_configuration {
      ipv4_enabled = true
      ssl_mode     = "ENCRYPTED_ONLY" # TLS obligatorio; sin authorized_networks nadie entra por la IP publica.
    }

    backup_configuration {
      enabled                        = var.backups_enabled
      point_in_time_recovery_enabled = var.backups_enabled
    }

    database_flags {
      name  = "log_checkpoints"
      value = "on"
    }
    database_flags {
      name  = "log_connections"
      value = "on"
    }
    database_flags {
      name  = "log_disconnections"
      value = "on"
    }
    database_flags {
      name  = "log_hostname"
      value = "on"
    }
    database_flags {
      name  = "log_min_messages"
      value = "error"
    }
    database_flags {
      name  = "log_statement"
      value = "ddl"
    }
    database_flags {
      name  = "log_lock_waits"
      value = "on"
    }
  }
}

resource "google_sql_database" "this" {
  name     = var.database_name
  instance = google_sql_database_instance.this.name
  project  = var.project_id
}

resource "google_sql_user" "admin" {
  name     = var.admin_login
  instance = google_sql_database_instance.this.name
  project  = var.project_id
  password = random_password.admin.result
}
