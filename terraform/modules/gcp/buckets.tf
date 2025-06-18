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

# Bind GKE Bucket to restic service account in the restic namespace
resource "google_storage_bucket_iam_member" "gke-backup-bucket-restic" {
	bucket = google_storage_bucket.gke-backup-bucket.name
	member = "principal://iam.googleapis.com/projects/${data.google_project.default.number}/locations/global/workloadIdentityPools/${data.google_project.default.project_id}.svc.id.goog/subject/ns/restic/sa/restic"
	role   = "roles/storage.objectUser"
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

resource "google_service_account_iam_binding" "debian-apt-repo" {
	service_account_id = google_service_account.debian-apt-repo.id
	role               = "roles/iam.workloadIdentityUser"
	members = [
		"serviceAccount:${data.google_project.default.project_id}.svc.id.goog[reprepro/reprepro]"
	]
}

# endregion Debian Apt Repository Bucket
