variable "name" {
  description = "Sufijo comun de los recursos."
  type        = string
}

variable "project_id" {
  description = "Proyecto de GCP."
  type        = string
}

variable "region" {
  description = "Region de Cloud Run."
  type        = string
}

variable "image" {
  description = "Imagen del contenedor en Artifact Registry."
  type        = string
}

variable "sql_connection_name" {
  description = "proyecto:region:instancia de Cloud SQL."
  type        = string
}

variable "secret_ids" {
  description = "Debe incluir database-url y jwt-secret (secret_id de Secret Manager)."
  type        = map(string)

  validation {
    condition     = alltrue([for name in ["database-url", "jwt-secret"] : contains(keys(var.secret_ids), name)])
    error_message = "secret_ids debe incluir database-url y jwt-secret."
  }
}

variable "environment_variables" {
  description = "Variables de entorno no secretas."
  type        = map(string)
  default     = {}
}

variable "min_instances" {
  description = "Con 0 la app escala a cero y no consume computo sin trafico."
  type        = number
  default     = 0
}

variable "max_instances" {
  description = "Tope de instancias; limita tambien el costo maximo."
  type        = number
  default     = 1
}

variable "iam_propagation_wait" {
  description = "Espera tras asignar los permisos de lectura."
  type        = string
  default     = "30s"
}

variable "labels" {
  description = "Etiquetas."
  type        = map(string)
  default     = {}
}
