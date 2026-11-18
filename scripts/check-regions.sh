#!/usr/bin/env bash
# Muestra las regiones de Cloud Run y confirma que Cloud SQL ofrece db-f1-micro con PostgreSQL 15.
source "$(dirname "$0")/lib.sh"
use_gcloud_identity

echo
echo "Regiones de Cloud Run (primeras 15):"
gcloud run regions list --format='value(locationId)' 2>/dev/null | head -15 | tr '\n' ' '
echo
echo
echo "Cloud SQL: regiones donde existe la maquina db-f1-micro:"
gcloud sql tiers list --format='value(tier,region.list())' 2>/dev/null \
  | awk '$1 == "db-f1-micro" {print "  " $0}'
echo
echo "Recomendado: us-central1 (capa gratuita de Cloud Run y precios de nivel 1)."
