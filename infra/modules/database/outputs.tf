output "connection_name" {
  description = "proyecto:region:instancia, usado por el conector de Cloud SQL de Cloud Run."
  value       = google_sql_database_instance.this.connection_name
}

output "instance_name" {
  description = "Nombre de la instancia."
  value       = google_sql_database_instance.this.name
}

output "database_url" {
  description = "URL SQLAlchemy por socket Unix del conector de Cloud SQL (el conector cifra el trafico)."
  sensitive   = true
  value = format(
    "postgresql+psycopg2://%s:%s@/%s?host=/cloudsql/%s",
    var.admin_login,
    urlencode(random_password.admin.result),
    var.database_name,
    google_sql_database_instance.this.connection_name,
  )
}
