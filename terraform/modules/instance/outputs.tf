# Copyright (c) 2026. Anshul Gupta
# All rights reserved.

output "hostname" {
  value = local.hostname
}

output "fqdn" {
  value = local.fqdn
}

output "id" {
  value = google_compute_instance.this.id
}

output "ipv4" {
  value = google_compute_address.ipv4.address
}

output "ipv6" {
  value = google_compute_address.ipv6.address
}

output "service_account" {
  value = google_service_account.this
}
