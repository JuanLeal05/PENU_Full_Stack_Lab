output "url" {
  description = "URL publica de la aplicacion."
  value       = google_cloud_run_v2_service.this.uri
}

output "service_name" {
  description = "Nombre del servicio de Cloud Run."
  value       = google_cloud_run_v2_service.this.name
}
