variable "konnect_server_url" {
  type        = string
  description = "Which Konnect instance to point at"
  default     = "https://us.api.konghq.com"
}

variable "konnect_token" {
  type        = string
  description = "API token to reach Konnect. Can be provided via TF_VAR_konnect_token environment variable."
  default     = null
  sensitive   = true
}

variable "auth_server_name" {
  type        = string
  description = "Name of the Kong Identity auth server"
  default     = "AcmeCo"
}

variable "auth_server_audience" {
  type        = string
  description = "Audience for the auth server"
  default     = "http://myhttpbin.dev"
}

variable "auth_server_description" {
  type        = string
  description = "Description of the auth server"
  default     = "Auth server for the Appointment dev environment"
}

variable "scope_name" {
  type        = string
  description = "Name of the scope for Kafka authentication"
  default     = "kafka"
}

variable "scope_description" {
  type        = string
  description = "Description of the scope"
  default     = "Scope to test Kong Identity"
}

variable "access_token_duration" {
  type        = number
  description = "Access token duration in seconds"
  default     = 3600
}

variable "id_token_duration" {
  type        = number
  description = "ID token duration in seconds"
  default     = 3600
}


