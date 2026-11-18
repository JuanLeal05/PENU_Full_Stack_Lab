mock_provider "google" {
  mock_resource "google_sql_database_instance" {
    defaults = {
      connection_name = "proyecto:us-central1:sql-prueba"
      name            = "sql-prueba"
    }
  }
}
mock_provider "random" {}

variables {
  instance_name = "sql-prueba"
  project_id    = "proyecto"
  region        = "us-central1"
}

run "usa_postgres_pequeno_y_tls_obligatorio" {
  command = apply

  assert {
    condition     = google_sql_database_instance.this.database_version == "POSTGRES_15"
    error_message = "La base debe ser PostgreSQL 15."
  }
  assert {
    condition     = google_sql_database_instance.this.settings[0].tier == "db-f1-micro"
    error_message = "Por defecto debe usarse la maquina mas barata."
  }
  assert {
    condition     = google_sql_database_instance.this.settings[0].ip_configuration[0].ssl_mode == "ENCRYPTED_ONLY"
    error_message = "La instancia debe exigir TLS."
  }
  assert {
    condition     = length(google_sql_database_instance.this.settings[0].ip_configuration[0].authorized_networks) == 0
    error_message = "No debe haber redes autorizadas: solo entra el conector de Cloud SQL."
  }
  assert {
    condition     = strcontains(nonsensitive(output.database_url), "host=/cloudsql/proyecto:us-central1:sql-prueba")
    error_message = "La URL debe conectar por el socket del conector de Cloud SQL."
  }
}

run "las_copias_son_opcionales" {
  command = apply

  variables {
    backups_enabled = true
  }

  assert {
    condition     = google_sql_database_instance.this.settings[0].backup_configuration[0].enabled
    error_message = "Las copias deben activarse con backups_enabled."
  }
}

run "solo_se_permiten_maquinas_baratas" {
  command = plan

  variables {
    tier = "db-n1-standard-8"
  }

  expect_failures = [var.tier]
}
