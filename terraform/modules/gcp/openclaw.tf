# Copyright (c) 2026. Anshul Gupta
# All rights reserved.

# Openclaw Server
resource "google_compute_instance" "openclaw" {
  name         = "openclaw-instance"
  machine_type = var.openclaw_machine_type
  zone         = var.auth_zone

  labels                    = var.common_labels
  allow_stopping_for_update = true

  boot_disk {
    auto_delete = true
    initialize_params {
      image = var.openclaw_image
      type  = var.openclaw_disk_type
      size  = var.openclaw_disk_size
    }
  }

  network_interface {
    network    = "default"
    subnetwork = data.google_compute_subnetwork.default-la.id
    stack_type = "IPV4_IPV6"

    # IPv4 access config
    access_config {
      network_tier           = "PREMIUM"
      nat_ip                 = google_compute_address.openclaw.address
      public_ptr_domain_name = "openclaw.${data.google_dns_managed_zone.default.dns_name}"
    }

    # IPv6 access config
    ipv6_access_config {
      network_tier                = "PREMIUM"
      external_ipv6               = google_compute_address.openclaw-ipv6.address
      external_ipv6_prefix_length = 96
    }
  }

  tags = [
    "openclaw"
  ]

  service_account {
    email  = google_service_account.openclaw.email
    scopes = ["cloud-platform"]
  }
}

# Service account for Openclaw Instance
resource "google_service_account" "openclaw" {
  account_id   = "openclaw"
  display_name = "Openclaw Server"
  description  = "Service account for Openclaw server instance"
}

# Allow openclaw Instance to retrieve CA certificate
resource "google_privateca_ca_pool_iam_member" "openclaw-ca" {
  ca_pool = google_privateca_ca_pool.default.id
  role    = "roles/privateca.certificateRequester"
  member  = "serviceAccount:${google_service_account.openclaw.email}"
}

# region Networking

# Static IPV4 address for Openclaw
resource "google_compute_address" "openclaw" {
  name         = "openclaw-static-ip"
  region       = var.auth_region
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
  network_tier = "PREMIUM"

  labels = var.common_labels
}

# Static IPv6 Address for openclaw Instance
resource "google_compute_address" "openclaw-ipv6" {
  name               = "openclaw-static-ipv6"
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
resource "google_compute_firewall" "openclaw-global" {
  name        = "openclaw-global-firewall"
  network     = "default"
  description = "Allow Wireguard traffic to Openclaw instance from anywhere (IPv4)"

  allow {
    protocol = "udp"
    ports    = ["51820"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["openclaw"]
}

# Allow SSH from specific IPs
resource "google_compute_firewall" "openclaw-ssh" {
  name        = "openclaw-ssh-firewall"
  network     = "default"
  description = "Allow SSH access to Openclaw instance from whitelisted IPs"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  priority      = 1000
  source_ranges = var.openclaw_ssh_allowed_ips
  target_tags   = ["openclaw"]
}

resource "google_compute_firewall" "openclaw-ssh-deny" {
  name        = "openclaw-ssh-deny-firewall"
  network     = "default"
  description = "Deny SSH access to Openclaw instance from non-whitelisted IPs"

  deny {
    protocol = "tcp"
    ports    = ["22"]
  }

  priority      = 1001
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["openclaw"]
}

# Deny SSH from all IPv6 sources
resource "google_compute_firewall" "openclaw-ssh-deny-ipv6" {
  name        = "openclaw-ssh-deny-firewall-ipv6"
  network     = "default"
  description = "Deny SSH (22/tcp) to Openclaw server from anywhere (IPv6)"

  deny {
    protocol = "tcp"
    ports    = ["22"]
  }

  priority      = 1001
  source_ranges = ["::/0"]
  target_tags   = ["openclaw"]
}
# endregion Networking
