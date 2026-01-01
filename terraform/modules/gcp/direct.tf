# Setup for anshulg.direct DNS rebinding

# DNS zone
data "google_dns_managed_zone" "direct" {
  name = var.dns_zone_anshulg_direct
}

# Service account for cert-manager
resource "google_service_account" "dns01-solver" {
  account_id   = "dns01-solver"
  display_name = "cert-manager DNS-01 Solver"
  description  = "Service account for cert-manager to solve DNS-01 ACME challenges (anshulg.direct zone)"
}

# Give the service account the ability to manage the DNS zone
resource "google_project_iam_member" "dns_admin" {
  project = data.google_project.default.project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.dns01-solver.email}"
}
