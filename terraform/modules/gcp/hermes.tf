# Copyright (c) 2026. Anshul Gupta
# All rights reserved.

# Hermes Server
resource "google_compute_instance" "hermes" {
  name         = "hermes-instance"
  machine_type = var.hermes_machine_type
  zone         = var.auth_zone

  labels                    = var.common_labels
  allow_stopping_for_update = true

  boot_disk {
    auto_delete = true
    initialize_params {
      image = var.hermes_image
      type  = var.hermes_disk_type
      size  = var.hermes_disk_size
    }
  }

  network_interface {
    network    = "default"
    subnetwork = data.google_compute_subnetwork.default-la.id
    stack_type = "IPV4_IPV6"

    # IPv4 access config
    access_config {
      network_tier           = "PREMIUM"
      nat_ip                 = google_compute_address.hermes.address
      public_ptr_domain_name = "hermes.${data.google_dns_managed_zone.default.dns_name}"
    }

    # IPv6 access config
    ipv6_access_config {
      network_tier                = "PREMIUM"
      external_ipv6               = google_compute_address.hermes-ipv6.address
      external_ipv6_prefix_length = 96
    }
  }

  tags = [
    "hermes"
  ]

  service_account {
    email  = google_service_account.hermes.email
    scopes = ["cloud-platform"]
  }
}

# Service account for Hermes Instance
resource "google_service_account" "hermes" {
  account_id   = "hermes"
  display_name = "Hermes Server"
  description  = "Service account for Hermes server instance"
}

# Allow Hermes Instance to retrieve CA certificate
resource "google_privateca_ca_pool_iam_member" "hermes-ca" {
  ca_pool = google_privateca_ca_pool.default.id
  role    = "roles/privateca.certificateRequester"
  member  = "serviceAccount:${google_service_account.hermes.email}"
}

# region Networking

# Static IPV4 address for Hermes
resource "google_compute_address" "hermes" {
  name         = "hermes-static-ip"
  region       = var.auth_region
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
  network_tier = "PREMIUM"

  labels = var.common_labels
}

# Static IPv6 Address for Hermes Instance
resource "google_compute_address" "hermes-ipv6" {
  name               = "hermes-static-ipv6"
  region             = var.auth_region
  address_type       = "EXTERNAL"
  ip_version         = "IPV6"
  network_tier       = "PREMIUM"
  subnetwork         = data.google_compute_subnetwork.default-la.id
  ipv6_endpoint_type = "VM"

  labels = var.common_labels
}

# Firewall rules
# Allow Wireguard traffic (IPv4)
resource "google_compute_firewall" "hermes-global" {
  name        = "hermes-global-firewall"
  network     = "default"
  description = "Allow Wireguard traffic to Hermes instance from anywhere (IPv4)"

  allow {
    protocol = "udp"
    ports    = ["51820"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["hermes"]
}

# Allow SSH from specific IPs
resource "google_compute_firewall" "hermes-ssh" {
  name        = "hermes-ssh-firewall"
  network     = "default"
  description = "Allow SSH access to Hermes instance from whitelisted IPs"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  priority      = 1000
  source_ranges = var.hermes_ssh_allowed_ips
  target_tags   = ["hermes"]
}

resource "google_compute_firewall" "hermes-ssh-deny" {
  name        = "hermes-ssh-deny-firewall"
  network     = "default"
  description = "Deny SSH access to Hermes instance from non-whitelisted IPs"

  deny {
    protocol = "tcp"
    ports    = ["22"]
  }

  priority      = 1001
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["hermes"]
}

# Deny SSH from all IPv6 sources
resource "google_compute_firewall" "hermes-ssh-deny-ipv6" {
  name        = "hermes-ssh-deny-firewall-ipv6"
  network     = "default"
  description = "Deny SSH (22/tcp) to Hermes server from anywhere (IPv6)"

  deny {
    protocol = "tcp"
    ports    = ["22"]
  }

  priority      = 1001
  source_ranges = ["::/0"]
  target_tags   = ["hermes"]
}
# endregion Networking
