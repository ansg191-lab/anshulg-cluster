# Private CA Outputs
output "ca_pool_id" {
  description = "The ID of the Private CA pool"
  value       = google_privateca_ca_pool.default.id
}

output "ca_pool_name" {
  description = "The name of the Private CA pool"
  value       = google_privateca_ca_pool.default.name
}

# KanIDM Instance Outputs
output "kanidm_instance_name" {
  description = "The name of the KanIDM instance"
  value       = google_compute_instance.kanidm.name
}

output "kanidm_static_ip" {
  description = "The static IP address of the KanIDM instance"
  value       = google_compute_address.kanidm.address
}

output "kanidm_static_ipv6" {
  description = "The static IPv6 address of the KanIDM instance"
  value       = google_compute_address.kanidm-ipv6.address
}

# Service Account Outputs
output "service_accounts" {
  description = "Service account emails by purpose"
  value = {
    kanidm               = google_service_account.kanidm.email
    github_action        = google_service_account.github-action.email
    cluster              = google_service_account.default.email
    cas_issuer           = google_service_account.sa-google-cas-issuer.email
    rpi4_cas_issuer      = google_service_account.rpi4-postgres-cas-issuer.email
    rpi5_cas_issuer      = google_service_account.rpi5-cas-issuer.email
    dns01_solver         = google_service_account.dns01-solver.email
    debian_apt_repo      = google_service_account.debian-apt-repo.email
  }
}

# Storage Bucket Outputs
output "bucket_names" {
  description = "Storage bucket names by purpose"
  value = {
    restic_backup = google_storage_bucket.gke-backup-bucket.name
    debian_apt    = google_storage_bucket.debian-apt-repo.name
  }
}

output "bucket_urls" {
  description = "Storage bucket URLs"
  value = {
    restic_backup = google_storage_bucket.gke-backup-bucket.url
    debian_apt    = google_storage_bucket.debian-apt-repo.url
  }
}

# DNS Zone Outputs
output "dns_zones" {
  description = "Managed DNS zones"
  value = {
    anshulg_com    = data.google_dns_managed_zone.default.name
    anshulg_direct = data.google_dns_managed_zone.direct.name
  }
}
