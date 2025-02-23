# Kandim Server
resource "google_compute_instance" "kanidm" {
  name         = "kanidm-instance"
  machine_type = "n1-standard-1"
  zone         = "us-west2-b"

  allow_stopping_for_update = true

  boot_disk {
    auto_delete = true
    initialize_params {
      image = "projects/opensuse-cloud/global/images/opensuse-leap-15-6-v20241004-x86-64"
      type  = "pd-balanced"
      size  = 20
    }
  }

  network_interface {
    network = "default"
    access_config {
      network_tier           = "PREMIUM"
      nat_ip                 = google_compute_address.kanidm.address
      public_ptr_domain_name = "auth.${data.google_dns_managed_zone.default.dns_name}"
    }
  }

  tags = [
    "http-server",
    "https-server",
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
  display_name = "Kanidm Service Account"
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
  region       = "us-west2"
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
  network_tier = "PREMIUM"
}

# Firewall rule for kanidm Instance
# Allow HTTP, HTTPS, and LDAPS traffic
resource "google_compute_firewall" "kanidm" {
  name    = "kanidm-firewall"
  network = "default"

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

# Add DNS record for kanidm Instance
# auth.anshulg.com
resource "google_dns_record_set" "auth-ipv4" {
  managed_zone = data.google_dns_managed_zone.default.name
  name         = "auth.${data.google_dns_managed_zone.default.dns_name}"
  type         = "A"
  ttl          = 60
  rrdatas = [
    google_compute_address.kanidm.address
  ]
}

# ldap.auth.anshulg.com
resource "google_dns_record_set" "ldap-ipv4" {
  managed_zone = data.google_dns_managed_zone.default.name
  name         = "ldap.auth.${data.google_dns_managed_zone.default.dns_name}"
  type         = "A"
  ttl          = 60
  rrdatas = [
    google_compute_address.kanidm.address
  ]
}

# endregion Networking

# region Deployment

# Create Service Account for Github Action Deployment
resource "google_service_account" "github-action" {
  account_id   = "github-action-anshulg"
  display_name = "Github Action Service Account for anshulg-cluster"
}

# Allow Github Action Service Account to ssh into kanidm Instance
resource "google_project_iam_binding" "instance_admin" {
  project = data.google_project.default.id
  role    = "roles/compute.instanceAdmin.v1"
  members = [
    "serviceAccount:${google_service_account.github-action.email}",
  ]
}

resource "google_project_iam_binding" "service_account_user" {
  project = data.google_project.default.id
  role    = "roles/iam.serviceAccountUser"
  members = [
    "serviceAccount:${google_service_account.github-action.email}",
  ]
}

resource "google_project_iam_member" "gh-action-dns-admin" {
  project = data.google_project.default.id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.github-action.email}"
}

# endregion Deployment

# region Backups

resource "google_compute_resource_policy" "scheduled_backup" {
  name   = "kanidm-scheduled-backup-policy"
  region = "us-west2"
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
      max_retention_days    = 7
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
