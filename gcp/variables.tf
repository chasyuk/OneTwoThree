variable "project_id" {
  description = "The Google Cloud Project ID (e.g. spry-chasyuk-2026)"
  type        = string
}

variable "region" {
  description = "Google Cloud region for resources"
  type        = string
  default     = "us-central1"
}

variable "app_name" {
  description = "Application name prefix"
  type        = string
  default     = "spry"
}

variable "backend_image" {
  description = "Container image URL for the FastAPI backend"
  type        = string
  default     = ""
}
