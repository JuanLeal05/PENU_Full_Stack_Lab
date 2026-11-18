# Seguridad y excepciones de Checkov

Checkov termina sin fallos porque los controles pasan o se omiten explícitamente. **Eso no significa
que esta configuración esté lista para producción real.** Cada omisión es un riesgo aceptado para no
consumir el crédito, y su razón está junto al recurso, en un comentario `#checkov:skip`.

## Lo que sí está protegido

- Solo HTTPS en Cloud Run y TLS obligatorio en Cloud SQL (`ssl_mode = ENCRYPTED_ONLY`).
- Secretos en Secret Manager, leídos con una cuenta de servicio que solo tiene `secretAccessor`.
- Estado de Terraform en un bucket sin acceso público, con versionado y sin llaves de acceso.
- GitHub entra con Workload Identity Federation: no hay llave JSON. La condición del proveedor limita el acceso a este repositorio.
- El desplegador solo puede otorgar dos roles (`cloudsql.client` y `secretmanager.secretAccessor`) gracias a una condición IAM.
- Contraseñas con scrypt, JWT con algoritmo fijo, imagen por digest y usuario sin privilegios.
- Montos enteros, restricción `CHECK` de saldo y claves de idempotencia únicas.

## Riesgos aceptados

| Riesgo | Para producción real |
|---|---|
| Cloud SQL conserva IP pública (sin redes autorizadas, solo entra el conector) | VPC con Private Service Connect o IP privada y Serverless VPC Access / Direct VPC egress |
| Secret Manager accesible desde la red pública | VPC Service Controls |
| La app entra a la base con usuario y contraseña de administrador | IAM database authentication con permisos mínimos |
| Sin auditoría de sentencias (pgaudit) ni Cloud Audit Logs de datos | Habilitarlos y enviarlos a un sink |
| Secretos sin rotación | Rotación automatizada con Secret Manager |
| Sin alta disponibilidad ni réplicas | `availability_type = REGIONAL` y réplica de lectura |
| Sin CMEK | Cloud KMS si la norma lo exige |
| `deletion_protection = false` en Cloud SQL | `true` en producción real |
| Aplicación pública (`allUsers` invoker) | Cloud Armor / Identity-Aware Proxy según el caso |

## Otros límites de la aplicación

- No hay límite de intentos de login ni de registros: agrégalo antes de exponer la app a usuarios reales.
- El bono de bienvenida crea dinero al registrarse: es solo una ayuda para la demostración.

## Ejecutar el análisis

```bash
uvx --python 3.12 checkov --config-file .checkov.yaml
```
