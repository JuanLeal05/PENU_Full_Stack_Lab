# Ledger: laboratorio de aplicación transaccional en GCP

Paquete del laboratorio (adaptado de Azure a Google Cloud). Siga la guía: cada paso se explica, y este
repositorio no se despliega ejecutando un solo comando.

| Carpeta | Contenido |
|---|---|
| `app/` | API FastAPI, interfaz web, pruebas y Dockerfile |
| `infra/bootstrap/` | Bucket de estado, Artifact Registry y Workload Identity Federation para GitHub Actions |
| `infra/modules/` | Módulos `database` (Cloud SQL), `secret_manager`, `cloud_run` y `stack` |
| `infra/environments/` | Raíces de `dev` y `prod` |
| `.github/workflows/` | Pipelines: `ci`, `publish-image`, `deploy`, `deploy-env` y `destroy` |
| `cost/` | Estimador de costos con tarifas públicas de GCP |
| `scripts/` | Consulta de regiones, prueba de humo y de concurrencia |
| `docs/` | Riesgos aceptados |
