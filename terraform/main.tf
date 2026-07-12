module "gcp" {
  source = "./modules/gcp"
}

module "vault" {
  source = "./modules/instance"

  role         = "vt"
  index        = 1
  machine_type = "n4a-standard-1"
  region       = "us-west1"
  zone         = "us-west1-c"

  boot_disk_os      = "debian-13-arm64"
  boot_disk_project = "debian-cloud"
  boot_disk_size_gb = 50
  boot_disk_type    = "hyperdisk-balanced"

  allowed_tcp_ports = [80, 443]
  allowed_udp_ports = [443]
  ssh_allowed_ips   = ["72.219.136.19/32"]

  create_service_account = true
}

# Create a KMS key ring
resource "google_kms_key_ring" "key_ring" {
  name     = "vault-ring"
  location = "us-west1"
}

# Create a crypto key for the key ring
resource "google_kms_crypto_key" "crypto_key" {
  name            = "vault-key"
  key_ring        = google_kms_key_ring.key_ring.id
  rotation_period = "7776000s"
  purpose         = "ENCRYPT_DECRYPT"

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "HSM"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_kms_crypto_key_iam_member" "vault_encrypter_decrypter" {
  crypto_key_id = google_kms_crypto_key.crypto_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = module.vault.service_account.member
}

resource "google_kms_crypto_key_iam_member" "vault_viewer" {
  crypto_key_id = google_kms_crypto_key.crypto_key.id
  role          = "roles/cloudkms.viewer"
  member        = module.vault.service_account.member
}
