# GKE Cluster Service Account
# Note: GKE cluster is currently deleted but service account is kept for future use
resource "google_service_account" "default" {
  account_id   = "cluster-service-account"
  display_name = "GKE Cluster Node Service Account"
  description  = "Service account for GKE cluster nodes (cluster currently deleted, kept for future use)"
}
