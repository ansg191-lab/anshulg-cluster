resource "google_privateca_ca_pool" "default" {
  name     = var.ca_pool_name
  location = var.primary_region
  tier     = var.ca_pool_tier
  publishing_options {
    publish_ca_cert = true
    publish_crl     = false
  }
}

resource "google_privateca_certificate_authority" "default" {
  pool                     = google_privateca_ca_pool.default.name
  location                 = var.primary_region
  certificate_authority_id = var.ca_name
  deletion_protection      = true
  config {
    subject_config {
      subject {
        common_name  = "Anshul Gupta Root CA"
        organization = "Anshul Gupta"
        province     = "California"
        country_code = "US"
      }
    }
    x509_config {
      ca_options {
        is_ca = true
      }
      key_usage {
        base_key_usage {
          digital_signature  = true
          content_commitment = true
          key_encipherment   = true
          data_encipherment  = true
          key_agreement      = true
          cert_sign          = true
          crl_sign           = true
          decipher_only      = true
        }
        extended_key_usage {
          server_auth      = true
          client_auth      = true
          email_protection = true
          code_signing     = true
          time_stamping    = true
        }
      }
    }
  }
  key_spec {
    algorithm = "EC_P384_SHA384"
  }
  lifetime = "315360000s"
}

resource "google_service_account" "sa-google-cas-issuer" {
  account_id = "sa-google-cas-issuer"
}

resource "google_service_account" "rpi4-postgres-cas-issuer" {
  account_id = "rpi4-postgres-cas-issuer"
}

resource "google_service_account" "rpi5-cas-issuer" {
  account_id = "rpi5-cas-issuer"
}

resource "google_privateca_ca_pool_iam_binding" "sa-google-cas-issuer" {
  ca_pool = google_privateca_ca_pool.default.id
  role    = "roles/privateca.certificateRequester"
  members = [
    "serviceAccount:${google_service_account.sa-google-cas-issuer.email}",
    "serviceAccount:${google_service_account.rpi4-postgres-cas-issuer.email}",
    "serviceAccount:${google_service_account.rpi5-cas-issuer.email}",
  ]
  location = var.primary_region
}
