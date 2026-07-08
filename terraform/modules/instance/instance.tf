# Copyright (c) 2026. Anshul Gupta
# All rights reserved.

resource "google_compute_instance" "this" {
  name         = local.hostname
  machine_type = var.machine_type
  hostname     = local.fqdn
  zone         = var.zone

  allow_stopping_for_update = true

  boot_disk {
    auto_delete = false
    source      = google_compute_disk.boot.self_link
  }

  network_interface {
    network    = "default"
    subnetwork = data.google_compute_subnetwork.default.id
    stack_type = "IPV4_IPV6"

    access_config {
      network_tier           = "PREMIUM"
      nat_ip                 = google_compute_address.ipv4.address
      public_ptr_domain_name = local.fqdn
    }

    ipv6_access_config {
      network_tier                = "PREMIUM"
      external_ipv6               = google_compute_address.ipv6.address
      external_ipv6_prefix_length = 96
    }
  }

  tags = [local.firewall_tag]

  dynamic "service_account" {
    for_each = google_service_account.this
    content {
      email  = service_account.value.email
      scopes = ["cloud-platform"]
    }
  }
}

data "google_compute_image" "boot_image" {
  family  = var.boot_disk_os
  project = var.boot_disk_project
}

resource "google_compute_disk" "boot" {
  name  = "${local.hostname}-boot"
  zone  = var.zone
  type  = var.boot_disk_type
  image = data.google_compute_image.boot_image.self_link
  size  = var.boot_disk_size_gb
}
