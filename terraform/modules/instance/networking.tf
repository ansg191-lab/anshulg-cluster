# Copyright (c) 2026. Anshul Gupta
# All rights reserved.

resource "google_compute_address" "ipv4" {
  name         = "${local.hostname}-static-ipv4"
  region       = var.region
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
  network_tier = "PREMIUM"
}

resource "google_compute_address" "ipv6" {
  name               = "${local.hostname}-static-ipv6"
  region             = var.region
  address_type       = "EXTERNAL"
  ip_version         = "IPV6"
  network_tier       = "PREMIUM"
  subnetwork         = data.google_compute_subnetwork.default.id
  ipv6_endpoint_type = "VM"
}

data "google_compute_subnetwork" "default" {
  name   = "default"
  region = var.region
}
