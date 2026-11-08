output "cloud_run_url" {
  description = "The HTTPS URL of the Spry backend on Cloud Run"
  value       = google_cloud_run_v2_service.api.uri
}

output "cloud_sql_connection_name" {
  description = "The connection name of the Cloud SQL PostgreSQL instance"
  value       = google_sql_database_instance.postgres.connection_name
}

output "database_public_ip" {
  description = "The public IPv4 address of the Cloud SQL instance"
  value       = google_sql_database_instance.postgres.public_ip_address
}

output "artifact_registry_repo" {
  description = "The Docker repository URL in Artifact Registry"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.backend.name}"
}

output "firebase_site_id" {
  description = "The site ID for Firebase Hosting"
  value       = google_firebase_hosting_site.default.site_id
}
