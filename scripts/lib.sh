# Funciones comunes. Se carga con `source`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

die() {
  echo "Error: $*" >&2
  exit 1
}

require() {
  local tool
  for tool in "$@"; do
    command -v "$tool" >/dev/null || die "falta '$tool' en el PATH"
  done
}

# Toda la autenticacion sale de `gcloud auth login`. No hay llaves JSON ni secretos de cliente.
use_gcloud_identity() {
  require gcloud
  GCP_PROJECT_ID="${GCP_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
  [[ -n "$GCP_PROJECT_ID" ]] || die "ejecuta primero: gcloud auth login y gcloud config set project <id>"
  export GCP_PROJECT_ID
  echo "Proyecto: $GCP_PROJECT_ID ($(gcloud config get-value account 2>/dev/null))"
}
