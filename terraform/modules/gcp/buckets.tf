# GKE Buckets

# region Backup GKE Bucket
resource "google_storage_bucket" "gke-backup-bucket" {
	name          = "restic-backup-bucket-9r6c"
	location      = "US"
	force_destroy = false

	uniform_bucket_level_access = true
	storage_class               = "STANDARD"
	public_access_prevention    = "enforced"

	hierarchical_namespace {
		enabled = true
	}
}
# endregion Backup GKE Bucket

# region Debian Apt Repository Bucket
resource "google_storage_bucket" "debian-apt-repo" {
	name          = "anshulg-debian-apt"
	location      = "US"
	force_destroy = false

	uniform_bucket_level_access = false
	storage_class               = "STANDARD"
	public_access_prevention    = "enforced"
}

resource "google_service_account" "debian-apt-repo" {
	account_id = "debian-apt-repo"
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
