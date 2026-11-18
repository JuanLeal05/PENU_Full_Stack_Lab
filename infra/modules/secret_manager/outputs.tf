output "secret_ids" {
  description = "ID completo de cada secreto, por nombre."
  value       = { for name, secret in google_secret_manager_secret.this : name => secret.secret_id }
}

output "secret_resource_ids" {
  description = "Nombre de recurso de cada secreto, para asignar permisos."
  value       = { for name, secret in google_secret_manager_secret.this : name => secret.id }
}
