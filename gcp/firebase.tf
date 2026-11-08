# Firebase Hosting configuration for Spry Frontend
resource "google_firebase_project" "default" {
  provider = google-beta
  project  = var.project_id

  depends_on = [
    google_project_service.apis["firebase.googleapis.com"]
  ]
}

resource "google_firebase_hosting_site" "default" {
  provider = google-beta
  project  = var.project_id
  site_id  = "${var.app_name}-${var.project_id}"

  depends_on = [google_firebase_project.default]
}
