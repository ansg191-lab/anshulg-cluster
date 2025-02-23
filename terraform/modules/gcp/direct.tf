# Setup for anshulg.direct DNS rebinding

# DNS zone
data "google_dns_managed_zone" "direct" {
  name = "anshulg-direct"
}

# Service account for cert-manager
resource "google_service_account" "dns01-solver" {
  account_id = "dns01-solver"
}

# Give the service account the ability to manage the DNS zone
resource "google_project_iam_member" "dns_admin" {
  project = data.google_project.default.project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.dns01-solver.email}"
}
