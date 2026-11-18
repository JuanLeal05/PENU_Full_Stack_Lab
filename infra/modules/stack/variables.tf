variable "environment" {
  description = "Ambiente: dev o prod."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "El ambiente debe ser dev o prod."
  }
}

variable "project_id" {
  description = "Proyecto de GCP."
  type        = string
}

variable "region" {
  description = "Region de la aplicacion y de la base (ver scripts/check-regions.sh)."
  type        = string
}

variable "image" {
  description = "Imagen fijada por digest, para que prod ejecute exactamente lo probado en dev."
  type        = string

  validation {
    condition     = can(regex("@sha256:[a-f0-9]{64}$", var.image))
    error_message = "La imagen debe fijarse por digest: registro/imagen@sha256:..."
  }
}

variable "max_instances" {
  description = "Tope de instancias."
  type        = number
  default     = 1

  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 3
    error_message = "max_instances debe estar entre 1 y 3 para proteger el credito."
  }
}

variable "jwt_minutes" {
  description = "Vigencia de los tokens."
  type        = number
  default     = 30
}

variable "iam_propagation_wait" {
  description = "Espera tras cada asignacion de permisos."
  type        = string
  default     = "30s"
}
