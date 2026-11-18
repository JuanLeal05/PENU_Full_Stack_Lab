# Se ejecuta una sola vez desde tu equipo, con el token de gcloud. Crea lo que GitHub Actions necesita
# antes de poder desplegar: el bucket de estado, el repositorio de imagenes y dos identidades que
# entran con Workload Identity Federation (OIDC). Su propio estado queda local.
#   export GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token)"

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

provider "google" {
  project = var.project_id
  region  = var.region
}

variable "project_id" {
  description = "Proyecto de GCP donde viven los dos ambientes."
  type        = string
}

variable "region" {
  description = "Region de la aplicacion, la base y el repositorio de imagenes."
  type        = string
}

variable "github_repository" {
  description = "Repositorio que puede desplegar, como usuario/repositorio."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$", var.github_repository))
    error_message = "Usa el formato usuario/repositorio."
  }
}

variable "github_repository_ids" {
  description = <<-EOT
    Repositorio con sus ID numericos, como usuario@123/repositorio@456. Los repositorios nuevos firman
    el token OIDC con este formato. Obtengalo con:
    gh api repos/usuario/repositorio --jq '"\(.owner.login)@\(.owner.id)/\(.name)@\(.id)"'
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.github_repository_ids == null || can(regex("^[A-Za-z0-9-]+@[0-9]+/[A-Za-z0-9._-]+@[0-9]+$", var.github_repository_ids))
    error_message = "Usa el formato usuario@123/repositorio@456."
  }
}

data "google_project" "this" {
  project_id = var.project_id
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

locals {
  labels = { project = "eci-ledger-lab", managed_by = "terraform" }
  member = "serviceAccount"
}

# Estado remoto: un archivo por ambiente, versionado, sin acceso publico y sin claves.
resource "google_storage_bucket" "state" {
  #checkov:skip=CKV_GCP_62:Los logs de acceso al bucket generan almacenamiento adicional con costo
  #checkov:skip=CKV_GCP_78:El versionado esta activo; este control exige ademas una regla de ciclo de vida que no aplica
  name                        = "tfstate-ledger-${random_string.suffix.result}"
  project                     = var.project_id
  location                    = upper(var.region)
  force_destroy               = true
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  labels                      = local.labels

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 5
    }
    action {
      type = "Delete"
    }
  }
}

# Repositorio de imagenes: la imagen se identifica por su digest y las dos identidades solo escriben/leen aqui.
resource "google_artifact_registry_repository" "ledger" {
  #checkov:skip=CKV_GCP_84:Claves administradas por Google; CMEK exige Cloud KMS, que tiene costo
  project       = var.project_id
  location      = var.region
  repository_id = "ledger"
  format        = "DOCKER"
  description   = "Imagenes de Ledger"
  labels        = local.labels
}

# Identidad que publica la imagen: solo puede escribir en el repositorio.
resource "google_service_account" "publisher" {
  project      = var.project_id
  account_id   = "sa-ledger-publisher"
  display_name = "GitHub Actions: publicar imagen"
}

# Identidad que despliega: Terraform crea los recursos de cada ambiente.
resource "google_service_account" "deployer" {
  project      = var.project_id
  account_id   = "sa-ledger-deployer"
  display_name = "GitHub Actions: desplegar ambientes"
}

# Workload Identity Federation: no hay llave JSON ni secreto. GitHub firma un token OIDC y GCP lo
# acepta solo si viene de este repositorio.
resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = "ledger-github-pool"
  display_name              = "GitHub Actions"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  #checkov:skip=CKV_GCP_125:La condicion ya fija propietario y repositorio; ademas cada identidad solo acepta subjects de dev/prod o de main
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
  }
  # Ningun otro repositorio puede intercambiar su token, aunque conozca los identificadores.
  attribute_condition = "assertion.repository_owner == \"${split("/", var.github_repository)[0]}\" && assertion.repository == \"${var.github_repository}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Subjects permitidos. Con nombres (repositorios anteriores) y con ID numericos (los nuevos).
locals {
  repo_prefixes = compact([var.github_repository, var.github_repository_ids])

  deploy_subjects = flatten([
    for prefix in local.repo_prefixes : [for environment in ["dev", "prod"] : "repo:${prefix}:environment:${environment}"]
  ])
  publish_subjects = [for prefix in local.repo_prefixes : "repo:${prefix}:ref:refs/heads/main"]

  pool = google_iam_workload_identity_pool.github.name
}

resource "google_service_account_iam_member" "deployer_wif" {
  for_each = toset(local.deploy_subjects)

  service_account_id = google_service_account.deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${local.pool}/subject/${each.value}"
}

resource "google_service_account_iam_member" "publisher_wif" {
  for_each = toset(local.publish_subjects)

  service_account_id = google_service_account.publisher.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${local.pool}/subject/${each.value}"
}

resource "google_artifact_registry_repository_iam_member" "publisher" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.ledger.repository_id
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.publisher.email}"
}

resource "google_storage_bucket_iam_member" "deployer_state" {
  bucket = google_storage_bucket.state.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.deployer.email}"
}

# Roles amplios del desplegador, a nivel de proyecto porque Terraform crea servicios, bases y secretos.
resource "google_project_iam_member" "deployer" {
  #checkov:skip=CKV_GCP_41:iam.serviceAccountUser es necesario para que Cloud Run ejecute con la cuenta de la app
  #checkov:skip=CKV_GCP_49:serviceAccountAdmin se usa solo para crear la cuenta de cada app
  for_each = toset([
    "roles/run.admin",
    "roles/cloudsql.admin",
    "roles/secretmanager.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
    "roles/logging.configWriter",
    "roles/serviceusage.serviceUsageConsumer",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.deployer.email}"
}

# Los roles anteriores no pueden asignar roles de proyecto. Este permiso lo habilita, limitado por la
# condicion a dos roles: el pipeline no puede otorgarse Owner a si mismo.
resource "google_project_iam_member" "deployer_iam_admin" {
  project = var.project_id
  role    = "roles/resourcemanager.projectIamAdmin"
  member  = "serviceAccount:${google_service_account.deployer.email}"

  condition {
    title       = "solo-roles-de-la-app"
    description = "Solo puede otorgar o quitar cloudsql.client y secretmanager.secretAccessor"
    expression  = <<-EOT
      api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly([
        'roles/cloudsql.client',
        'roles/secretmanager.secretAccessor'
      ])
    EOT
  }
}

output "workload_identity_provider" {
  description = "Recurso del proveedor OIDC. No es un secreto."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "deployer_service_account" {
  value = google_service_account.deployer.email
}

output "publisher_service_account" {
  value = google_service_account.publisher.email
}

output "project_id" {
  value = var.project_id
}

output "region" {
  value = var.region
}

output "state_bucket" {
  value = google_storage_bucket.state.name
}

output "registry" {
  description = "Ruta base de las imagenes."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.ledger.repository_id}"
}
