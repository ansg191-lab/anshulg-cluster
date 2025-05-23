# GKE Buckets

# Test GKE Bucket
resource "google_storage_bucket" "gke-test-bucket" {
	name          = "gke-test-bucket-lvmn"
	location      = "US"
	force_destroy = true

	uniform_bucket_level_access = true
	storage_class               = "STANDARD"
	public_access_prevention    = "enforced"
}

# Bind GKE Bucket to default service account in the default namespace
resource "google_storage_bucket_iam_member" "gke-test-bucket-default" {
	bucket = google_storage_bucket.gke-test-bucket.name
	member = "principal://iam.googleapis.com/projects/${data.google_project.default.number}/locations/global/workloadIdentityPools/${data.google_project.default.project_id}.svc.id.goog/subject/ns/default/sa/default"
	role   = "roles/storage.objectUser"
}

# Backup GKE Bucket
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

# Bind GKE Bucket to restic service account in the restic  namespace
resource "google_storage_bucket_iam_member" "gke-backup-bucket-restic" {
	bucket = google_storage_bucket.gke-backup-bucket.name
	member = "principal://iam.googleapis.com/projects/${data.google_project.default.number}/locations/global/workloadIdentityPools/${data.google_project.default.project_id}.svc.id.goog/subject/ns/restic/sa/restic"
	role   = "roles/storage.objectUser"
}

# Cockroach Backup Bucket
resource "google_storage_bucket" "gke-cockroach-bucket" {
	name          = "cockroacchdb-backup-bucket-8kmcx"
	location      = "US"
	force_destroy = false

	uniform_bucket_level_access = true
	storage_class               = "COLDLINE"
	public_access_prevention    = "enforced"
}

# Bind GKE bucket to cockroachdb-sa service account in the miniflux namespace
resource "google_storage_bucket_iam_member" "gke-cockroach-bucket-miniflux" {
	bucket = google_storage_bucket.gke-cockroach-bucket.name
	member = "principal://iam.googleapis.com/projects/${data.google_project.default.number}/locations/global/workloadIdentityPools/${data.google_project.default.project_id}.svc.id.goog/subject/ns/miniflux/sa/cockroachdb-sa"
	role   = "roles/storage.objectUser"
}

# KanIDM Backup Bucket
resource "google_storage_bucket" "gke-kanidm-bucket" {
	name          = "kanidm-backup-bucket-wzqjn"
	location      = "US"
	force_destroy = false

	uniform_bucket_level_access = true
	storage_class               = "NEARLINE"
	public_access_prevention    = "enforced"

	lifecycle_rule {
		condition {
			age = 30
		}
		action {
			type          = "SetStorageClass"
			storage_class = "ARCHIVE"
		}
	}
}

# Bind GKE bucket to cockroachdb-sa service account in the miniflux namespace
resource "google_storage_bucket_iam_member" "gke-kanidm-bucket-miniflux" {
	bucket = google_storage_bucket.gke-kanidm-bucket.name
	member = "principal://iam.googleapis.com/projects/${data.google_project.default.number}/locations/global/workloadIdentityPools/${data.google_project.default.project_id}.svc.id.goog/subject/ns/kanidm/sa/kanidm"
	role   = "roles/storage.objectUser"
}

# CloudnativePG Backup Bucket
resource "google_storage_bucket" "cnpg-backup-bucket" {
	name          = "cnpg-backup-bucket-eixpr"
	location      = "US"
	force_destroy = false

	uniform_bucket_level_access = true
	storage_class               = "STANDARD"
	public_access_prevention    = "enforced"
}

# region Kellnr Cluster Backups

resource "google_service_account" "cnpg-backup-kellnr" {
	account_id = "cnpg-backup-kellnr"
}

resource "google_storage_bucket_iam_member" "cnpg-backup-kellnr-bucket" {
	bucket = google_storage_bucket.cnpg-backup-bucket.name
	member = "serviceAccount:${google_service_account.cnpg-backup-kellnr.email}"
	role   = "roles/storage.legacyBucketWriter"
}

resource "google_storage_bucket_iam_member" "cnpg-backup-kellnr-object" {
	bucket = google_storage_bucket.cnpg-backup-bucket.name
	member = "serviceAccount:${google_service_account.cnpg-backup-kellnr.email}"
	role   = "roles/storage.legacyObjectOwner"
}

resource "google_service_account_iam_binding" "cnpg-backup-kellnr" {
	service_account_id = google_service_account.cnpg-backup-kellnr.id
	role               = "roles/iam.workloadIdentityUser"
	members = [
		"serviceAccount:${data.google_project.default.project_id}.svc.id.goog[kellnr/kellnr-cluster]"
	]
}

# endregion Kellnr Cluster Backups

# region Miniflux Cluster Backups

resource "google_service_account" "cnpg-backup-miniflux" {
	account_id = "cnpg-backup-miniflux"
}

resource "google_storage_bucket_iam_member" "cnpg-backup-miniflux-bucket" {
	bucket = google_storage_bucket.cnpg-backup-bucket.name
	member = "serviceAccount:${google_service_account.cnpg-backup-miniflux.email}"
	role   = "roles/storage.legacyBucketWriter"
}

resource "google_storage_bucket_iam_member" "cnpg-backup-miniflux-object" {
	bucket = google_storage_bucket.cnpg-backup-bucket.name
	member = "serviceAccount:${google_service_account.cnpg-backup-miniflux.email}"
	role   = "roles/storage.legacyObjectOwner"
}


resource "google_service_account_iam_binding" "cnpg-backup-miniflux" {
	service_account_id = google_service_account.cnpg-backup-miniflux.id
	role               = "roles/iam.workloadIdentityUser"
	members = [
		"serviceAccount:${data.google_project.default.project_id}.svc.id.goog[miniflux/miniflux-cluster]"
	]
}

# endregion Miniflux Cluster Backups

# region Paperless Cluster Backups

resource "google_service_account" "cnpg-backup-paperless" {
	account_id = "cnpg-backup-paperless"
}

resource "google_storage_bucket_iam_member" "cnpg-backup-paperless-bucket" {
	bucket = google_storage_bucket.cnpg-backup-bucket.name
	member = "serviceAccount:${google_service_account.cnpg-backup-paperless.email}"
	role   = "roles/storage.legacyBucketWriter"
}

resource "google_storage_bucket_iam_member" "cnpg-backup-paperless-object" {
	bucket = google_storage_bucket.cnpg-backup-bucket.name
	member = "serviceAccount:${google_service_account.cnpg-backup-paperless.email}"
	role   = "roles/storage.legacyObjectOwner"
}

# endregion Paperless Cluster Backups

# region Debian Apt Repository Bucket
resource "google_storage_bucket" "debian-apt-repo" {
	name          = "anshulg-debian-apt"
	location      = "US"
	force_destroy = false

	uniform_bucket_level_access = true
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
