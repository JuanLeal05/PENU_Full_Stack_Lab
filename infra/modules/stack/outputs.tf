output "app_url" {
  description = "URL publica de la aplicacion."
  value       = module.app.url
}

output "service_name" {
  description = "Servicio de Cloud Run del ambiente."
  value       = module.app.service_name
}

output "sql_instance" {
  description = "Instancia de Cloud SQL del ambiente."
  value       = module.database.instance_name
}
