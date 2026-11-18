# Pruebas sin nube: mock_provider no necesita credenciales ni proyecto real.

mock_provider "google" {
  mock_resource "google_sql_database_instance" {
    defaults = {
      connection_name = "proyecto:us-central1:sql"
      name            = "sql"
    }
  }
  mock_resource "google_secret_manager_secret" {
    defaults = {
      id        = "projects/proyecto/secrets/secreto"
      secret_id = "secreto"
    }
  }
  mock_resource "google_service_account" {
    defaults = {
      email = "sa@proyecto.iam.gserviceaccount.com"
    }
  }
  mock_resource "google_cloud_run_v2_service" {
    defaults = {
      uri  = "https://ca-ledger-xyz.a.run.app"
      name = "ca-ledger"
    }
  }
}

mock_provider "random" {}
mock_provider "time" {}

variables {
  project_id           = "proyecto"
  region               = "us-central1"
  image                = "us-central1-docker.pkg.dev/proyecto/ledger/ledger@sha256:0000000000000000000000000000000000000000000000000000000000000000"
  iam_propagation_wait = "1s"
}

run "dev_es_desechable_y_sin_extras" {
  command = apply

  variables {
    environment = "dev"
  }

  assert {
    condition     = google_logging_metric.errors == []
    error_message = "dev no debe crear la metrica de errores."
  }
  assert {
    condition     = local.labels["environment"] == "dev"
    error_message = "Las etiquetas deben identificar el ambiente."
  }
  assert {
    condition     = startswith(output.app_url, "https://")
    error_message = "La URL publica debe ser HTTPS."
  }
  assert {
    condition     = local.is_prod == false
    error_message = "dev no debe activar la configuracion de prod."
  }
}

run "prod_se_protege" {
  command = apply

  variables {
    environment   = "prod"
    max_instances = 3
  }

  assert {
    condition     = length(google_logging_metric.errors) == 1
    error_message = "prod debe crear la metrica de errores."
  }
  assert {
    condition     = module.database.connection_name == "proyecto:us-central1:sql"
    error_message = "La app debe conectarse a la instancia del mismo ambiente."
  }
  assert {
    condition     = local.is_prod
    error_message = "prod debe activar copias de seguridad y metrica."
  }
}

run "la_imagen_debe_ir_por_digest" {
  command = plan

  variables {
    environment = "dev"
    image       = "us-central1-docker.pkg.dev/proyecto/ledger/ledger:latest"
  }

  expect_failures = [var.image]
}

run "ambiente_desconocido_se_rechaza" {
  command = plan

  variables {
    environment = "staging"
  }

  expect_failures = [var.environment]
}

run "el_tope_de_instancias_protege_el_credito" {
  command = plan

  variables {
    environment   = "prod"
    max_instances = 10
  }

  expect_failures = [var.max_instances]
}
