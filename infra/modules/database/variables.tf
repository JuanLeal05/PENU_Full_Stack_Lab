variable "instance_name" {
  description = "Nombre de la instancia de Cloud SQL (un nombre eliminado no se puede reutilizar durante una semana)."
  type        = string
}

variable "project_id" {
  description = "Proyecto de GCP."
  type        = string
}

variable "region" {
  description = "Region de Cloud SQL."
  type        = string
}

variable "database_name" {
  description = "Nombre de la base de datos."
  type        = string
  default     = "ledger"
}

variable "admin_login" {
  description = "Usuario de la aplicacion en PostgreSQL."
  type        = string
  default     = "ledgeradmin"
}

variable "tier" {
  description = "Tipo de maquina. db-f1-micro es el mas barato."
  type        = string
  default     = "db-f1-micro"

  validation {
    condition     = contains(["db-f1-micro", "db-g1-small"], var.tier)
    error_message = "Para proteger el credito solo se permiten db-f1-micro y db-g1-small."
  }
}

variable "backups_enabled" {
  description = "Copias de seguridad automaticas y recuperacion a un punto en el tiempo."
  type        = bool
  default     = false
}

variable "labels" {
  description = "Etiquetas."
  type        = map(string)
  default     = {}
}
