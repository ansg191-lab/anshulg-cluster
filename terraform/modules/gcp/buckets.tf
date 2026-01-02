# GKE Buckets

# region Backup GKE Bucket
resource "google_storage_bucket" "gke-backup-bucket" {
	name          = var.restic_bucket_name
	location      = var.bucket_location
	force_destroy = false

	labels = var.common_labels

	uniform_bucket_level_access = true
	storage_class               = var.bucket_storage_class
	public_access_prevention    = "enforced"

	hierarchical_namespace {
		enabled = true
	}
}
# endregion Backup GKE Bucket

# region Debian Apt Repository Bucket
resource "google_storage_bucket" "debian-apt-repo" {
	name          = var.debian_apt_bucket_name
	location      = var.bucket_location
	force_destroy = false

	labels = var.common_labels

	uniform_bucket_level_access = false
	storage_class               = var.bucket_storage_class
	public_access_prevention    = "enforced"
}

# endregion Debian Apt Repository Bucket
