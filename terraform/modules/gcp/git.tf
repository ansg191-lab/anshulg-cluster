# Git Server
resource "google_compute_instance" "git" {
	name         = "git-instance"
	machine_type = "e2-small"
	zone         = "us-west2-b"

	allow_stopping_for_update = true

	boot_disk {
		auto_delete = true
		initialize_params {
			image = "projects/debian-cloud/global/images/debian-12-bookworm-v20250311"
			type  = "pd-balanced"
			size  = 16
		}
	}

	network_interface {
		network    = data.google_compute_network.default.id
		subnetwork = data.google_compute_subnetwork.default-la.id
		stack_type = "IPV4_IPV6"
		access_config {
			network_tier           = "PREMIUM"
			nat_ip                 = google_compute_address.git.address
			public_ptr_domain_name = "git.${data.google_dns_managed_zone.default.dns_name}"
		}
		ipv6_access_config {
			network_tier           = "PREMIUM"
			public_ptr_domain_name = "git.${data.google_dns_managed_zone.default.dns_name}"
		}
	}

	tags = [
		"http-server",
		"https-server",
		"git-server"
	]

	attached_disk {
		source      = google_compute_disk.git.self_link
		device_name = "git-disk"
		mode        = "READ_WRITE"
	}

	hostname = "git.anshulg.com"
}

# region Networking

# Static IPV4 Address for git Instance
resource "google_compute_address" "git" {
	name         = "git-static-ip"
	region       = "us-west2"
	address_type = "EXTERNAL"
	ip_version   = "IPV4"
	network_tier = "PREMIUM"
}

# Firewall rule for git Instance
# Allow HTTP, HTTPS, and SSH traffic
resource "google_compute_firewall" "git" {
	name    = "git-firewall"
	network = "default"

	allow {
		protocol = "tcp"
		ports = ["22", "80", "443"]
	}

	allow {
		protocol = "udp"
		ports = ["443"]
	}

	source_ranges = ["0.0.0.0/0"]
	target_tags = ["git-server"]
}

# endregion Networking

# region Storage

resource "google_compute_disk" "git" {
	name = "git-disk"
	type = "pd-standard"
	zone = "us-west2-b"
	size = 32
}

resource "google_compute_resource_policy" "git_backup" {
	name   = "git-scheduled-backup"
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

resource "google_compute_disk_resource_policy_attachment" "git_backup" {
	name = google_compute_resource_policy.git_backup.name
	disk = google_compute_disk.git.name
	zone = google_compute_disk.git.zone
}

# endregion Storage
