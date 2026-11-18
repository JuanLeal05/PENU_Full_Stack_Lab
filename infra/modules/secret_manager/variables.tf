variable "project_id" {
  description = "Proyecto de GCP."
  type        = string
}

variable "region" {
  description = "Region donde se replica el secreto."
  type        = string
}

variable "prefix" {
  description = "Prefijo de los secretos, por ejemplo ledger-dev."
  type        = string
}

variable "secrets" {
  description = "Secretos a guardar, por nombre."
  type        = map(string)
  sensitive   = true
}

variable "labels" {
  description = "Etiquetas."
  type        = map(string)
  default     = {}
}
