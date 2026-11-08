resource "google_artifact_registry_repository" "backend" {
  location      = var.region
  repository_id = "${var.app_name}-backend"
  description   = "Docker repository for Spry backend API"
  format        = "DOCKER"

  depends_on = [google_project_service.apis["artifactregistry.googleapis.com"]]
}
