# Copyright (c) 2026. Anshul Gupta
# All rights reserved.

locals {
  firewall_tag      = "${local.hostname}-fw"
  has_allowed_ports = (length(var.allowed_tcp_ports) + length(var.allowed_udp_ports)) > 0
}

resource "google_compute_firewall" "allow_ipv4" {
  name        = "${local.hostname}-global-firewall-ipv4"
  network     = "default"
  description = "Allow inbound IPV4 traffic on allowed ports for ${local.hostname}."

  dynamic "allow" {
    for_each = var.allowed_tcp_ports
    content {
      protocol   = "TCP"
      ports = [tostring(allow.value)]
    }
  }

  dynamic "allow" {
    for_each = var.allowed_udp_ports
    content {
      protocol   = "UDP"
      ports = [tostring(allow.value)]
    }
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = [local.firewall_tag]

  count = local.has_allowed_ports ? 1 : 0
}


resource "google_compute_firewall" "allow_ipv6" {
  name        = "${local.hostname}-global-firewall-ipv6"
  network     = "default"
  description = "Allow inbound IPV6 traffic on allowed ports for ${local.hostname}."

  dynamic "allow" {
    for_each = var.allowed_tcp_ports
    content {
      protocol   = "TCP"
      ports = [tostring(allow.value)]
    }
  }

  dynamic "allow" {
    for_each = var.allowed_udp_ports
    content {
      protocol   = "UDP"
      ports = [tostring(allow.value)]
    }
  }

  source_ranges = ["::/0"]
  target_tags   = [local.firewall_tag]

  count = local.has_allowed_ports ? 1 : 0
}

# Allow ICMPv6 (ping6) from anywhere.
resource "google_compute_firewall" "icmpv6" {
  name        = "${local.hostname}-icmpv6-firewall"
  network     = "default"
  description = "Allow ICMPv6 traffic to ${local.hostname} for ping (IPv6)"

  allow {
    protocol = "58" # ICMPv6
  }

  source_ranges = ["::/0"]
  target_tags   = [local.firewall_tag]
}


# Allow SSH from whitelisted IPs.
resource "google_compute_firewall" "ssh_allow" {
  name        = "${local.hostname}-ssh-firewall"
  network     = "default"
  description = "Allow SSH (22/tcp) to ${local.hostname} from whitelisted IPs"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  priority      = 1000
  source_ranges = var.ssh_allowed_ips
  target_tags   = [local.firewall_tag]

  count = length(var.ssh_allowed_ips) > 0 ? 1 : 0
}

# Deny all other SSH (IPv4).
resource "google_compute_firewall" "ssh_deny" {
  name        = "${local.hostname}-ssh-deny-firewall"
  network     = "default"
  description = "Deny SSH (22/tcp) to ${local.hostname} from all other sources (default-deny) - IPv4"

  deny {
    protocol = "tcp"
    ports    = ["22"]
  }

  priority      = 1001
  source_ranges = ["0.0.0.0/0"]
  target_tags   = [local.firewall_tag]

  count = length(var.ssh_allowed_ips) > 0 ? 1 : 0
}

# Deny all other SSH (IPv6).
resource "google_compute_firewall" "ssh_deny_ipv6" {
  name        = "${local.hostname}-ssh-deny-firewall-ipv6"
  network     = "default"
  description = "Deny SSH (22/tcp) to ${local.hostname} from all other sources (default-deny) - IPv6"

  deny {
    protocol = "tcp"
    ports    = ["22"]
  }

  priority      = 1001
  source_ranges = ["::/0"]
  target_tags   = [local.firewall_tag]

  count = length(var.ssh_allowed_ips) > 0 ? 1 : 0
}
