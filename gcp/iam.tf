resource "google_service_account" "api_sa" {
  account_id   = "${var.app_name}-api-sa"
  display_name = "Service Account for Spry Backend API on Cloud Run"
  description  = "Dedicated identity with minimal permissions to connect to Cloud SQL and Secret Manager"
}

# Grant Cloud SQL Client role so Cloud Run can connect via Unix socket
resource "google_project_iam_member" "api_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.api_sa.email}"
}
