# Kandim Server
resource "google_compute_instance" "kanidm" {
  name         = "kanidm-instance"
  machine_type = var.kanidm_machine_type
  zone         = var.auth_zone

  labels                    = var.common_labels
  allow_stopping_for_update = true

  boot_disk {
    auto_delete = true
    initialize_params {
      image = var.kanidm_image
      type  = var.kanidm_disk_type
      size  = var.kanidm_disk_size
    }
  }

  network_interface {
    network    = "default"
    subnetwork = data.google_compute_subnetwork.default-la.id
    stack_type = "IPV4_IPV6"

    # IPv4 access config
    access_config {
      network_tier           = "PREMIUM"
      nat_ip                 = google_compute_address.kanidm.address
      public_ptr_domain_name = "auth.${data.google_dns_managed_zone.default.dns_name}"
    }

    # IPv6 access config
    ipv6_access_config {
      network_tier                = "PREMIUM"
      external_ipv6               = google_compute_address.kanidm-ipv6.address
      external_ipv6_prefix_length = 96
      public_ptr_domain_name      = "auth.${data.google_dns_managed_zone.default.dns_name}"
    }
  }

  tags = [
    "kanidm"
  ]

  service_account {
    email  = google_service_account.kanidm.email
    scopes = ["cloud-platform"]
  }
}

# Service account for kanidm Instance
resource "google_service_account" "kanidm" {
  account_id   = "kanidm"
  display_name = "KanIDM Authentication Server"
  description  = "Service account for KanIDM authentication server instance with Private CA certificate access"
}

# Allow kanidm Instance to retrieve CA certificate
resource "google_privateca_ca_pool_iam_member" "kanidm-ca" {
  ca_pool = google_privateca_ca_pool.default.id
  role    = "roles/privateca.certificateManager"
  member  = "serviceAccount:${google_service_account.kanidm.email}"
}

# region Networking

# Static IPV4 Address for kanidm Instance
resource "google_compute_address" "kanidm" {
  name         = "kanidm-static-ip"
  region       = var.auth_region
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
  network_tier = "PREMIUM"

  labels = var.common_labels
}

# Static IPv6 Address for kanidm Instance
resource "google_compute_address" "kanidm-ipv6" {
  name               = "kanidm-static-ipv6"
  region             = var.auth_region
  address_type       = "EXTERNAL"
  ip_version         = "IPV6"
  network_tier       = "PREMIUM"
  subnetwork         = data.google_compute_subnetwork.default-la.id
  ipv6_endpoint_type = "VM"

  labels = var.common_labels
}

# Firewall rule for kanidm Instance (IPv4)
# Allow HTTP, HTTPS, HTTP/3 & LDAPS traffic
resource "google_compute_firewall" "kanidm-global" {
  name        = "kanidm-global-firewall"
  network     = "default"
  description = "Allow HTTP (80/tcp), HTTPS (443/tcp), LDAPS (636/tcp) and HTTP/3 QUIC (443/udp) traffic to KanIDM server from anywhere (IPv4)"

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "636"]
  }

  allow {
    protocol = "udp"
    ports    = ["443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["kanidm"]
}

# Firewall rule for kanidm Instance (IPv6)
# Allow HTTP, HTTPS, HTTP/3 & LDAPS traffic
resource "google_compute_firewall" "kanidm-global-ipv6" {
  name        = "kanidm-global-firewall-ipv6"
  network     = "default"
  description = "Allow HTTP (80/tcp), HTTPS (443/tcp), LDAPS (636/tcp) and HTTP/3 QUIC (443/udp) traffic to KanIDM server from anywhere (IPv6)"

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "636"]
  }

  allow {
    protocol = "udp"
    ports    = ["443"]
  }

  source_ranges = ["::/0"]
  target_tags   = ["kanidm"]
}

# Allow ICMPv6 (ping6) traffic
resource "google_compute_firewall" "kanidm-icmpv6" {
  name        = "kanidm-icmpv6-firewall"
  network     = "default"
  description = "Allow ICMPv6 traffic to KanIDM server for ping (IPv6)"

  allow {
    protocol = "58"  # ICMPv6
  }

  source_ranges = ["::/0"]
  target_tags   = ["kanidm"]
}

# Allow SSH traffic from specific IPs
resource "google_compute_firewall" "kanidm-ssh" {
  name        = "kanidm-ssh-firewall"
  network     = "default"
  description = "Allow SSH (22/tcp) to KanIDM server from whitelisted IPs (Cox ISP, UCR network)"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  priority      = 1000
  source_ranges = var.kanidm_ssh_allowed_ips
  target_tags   = ["kanidm"]
}
resource "google_compute_firewall" "kanidm-ssh-deny" {
  name        = "kanidm-ssh-deny-firewall"
  network     = "default"
  description = "Deny SSH (22/tcp) to KanIDM server from all other sources (default-deny) - IPv4"

  deny {
    protocol = "tcp"
    ports    = ["22"]
  }

  priority      = 1001
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["kanidm"]
}

# Deny SSH from all IPv6 sources
resource "google_compute_firewall" "kanidm-ssh-deny-ipv6" {
  name        = "kanidm-ssh-deny-firewall-ipv6"
  network     = "default"
  description = "Deny SSH (22/tcp) to KanIDM server from all other sources (default-deny) - IPv6"

  deny {
    protocol = "tcp"
    ports    = ["22"]
  }

  priority      = 1001
  source_ranges = ["::/0"]
  target_tags   = ["kanidm"]
}
# endregion Networking

# region Deployment

# Create Service Account for Github Action Deployment
resource "google_service_account" "github-action" {
  account_id   = "github-action-anshulg"
  display_name = "GitHub Actions Deployment"
  description  = "Service account for GitHub Actions to deploy auth-server (SSH, firewall, DNS access)"
}

# Allow Github Action Service Account to ssh into kanidm Instance
resource "google_project_iam_member" "instance_admin" {
  project = data.google_project.default.id
  role    = "roles/compute.instanceAdmin.v1"
  member  = "serviceAccount:${google_service_account.github-action.email}"
}

resource "google_project_iam_member" "service_account_user" {
  project = data.google_project.default.id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.github-action.email}"
}

resource "google_project_iam_member" "gh-action-dns-admin" {
  project = data.google_project.default.id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.github-action.email}"
}

resource "google_project_iam_member" "gh-action-firewalls" {
  project = data.google_project.default.id
  role    = "roles/compute.securityAdmin"
  member  = "serviceAccount:${google_service_account.github-action.email}"
}

# endregion Deployment

# region Backups

resource "google_compute_resource_policy" "scheduled_backup" {
  name   = "kanidm-scheduled-backup-policy"
  region = var.auth_region
  snapshot_schedule_policy {
    schedule {
      daily_schedule {
        days_in_cycle = 1
        start_time    = "8:00"
      }
    }
    snapshot_properties {
      storage_locations = ["us"]
    }
    retention_policy {
      max_retention_days    = var.kanidm_backup_retention_days
      on_source_disk_delete = "KEEP_AUTO_SNAPSHOTS"
    }
  }
}

resource "google_compute_disk_resource_policy_attachment" "kanidm" {
  name = google_compute_resource_policy.scheduled_backup.name
  disk = google_compute_instance.kanidm.name
  zone = google_compute_instance.kanidm.zone
}

# endregion Backups
