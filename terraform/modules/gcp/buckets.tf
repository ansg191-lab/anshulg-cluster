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

resource "google_service_account" "debian-apt-repo" {
	account_id   = "debian-apt-repo"
	display_name = "Debian APT Repository Manager"
	description  = "Service account for managing Debian APT repository bucket (legacy ACL access)"
}

resource "google_storage_bucket_iam_member" "debian-apt-repo-bucket" {
	bucket = google_storage_bucket.debian-apt-repo.name
	member = "serviceAccount:${google_service_account.debian-apt-repo.email}"
	role   = "roles/storage.legacyBucketWriter"
}

resource "google_storage_bucket_iam_member" "debian-apt-repo-object" {
	bucket = google_storage_bucket.debian-apt-repo.name
	member = "serviceAccount:${google_service_account.debian-apt-repo.email}"
	role   = "roles/storage.legacyObjectOwner"
}

# endregion Debian Apt Repository Bucket
