resource "google_privateca_ca_pool" "default" {
  name     = "default"
  location = "us-west1"
  tier     = "DEVOPS"
  publishing_options {
    publish_ca_cert = true
    publish_crl     = false
  }
}

resource "google_privateca_certificate_authority" "default" {
  pool                     = google_privateca_ca_pool.default.name
  location                 = "us-west1"
  certificate_authority_id = "anshul-ca-1"
  deletion_protection      = false
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

resource "google_privateca_ca_pool_iam_binding" "sa-google-cas-issuer" {
  ca_pool = google_privateca_ca_pool.default.id
  role    = "roles/privateca.certificateRequester"
  members = [
    "serviceAccount:${google_service_account.sa-google-cas-issuer.email}",
    "serviceAccount:rpi5-cas-issuer@anshulg-cluster.iam.gserviceaccount.com",
  ]
  location = "us-west1"
}

resource "google_service_account_iam_binding" "sa-google-cas-issuer" {
  service_account_id = google_service_account.sa-google-cas-issuer.id
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${data.google_project.default.project_id}.svc.id.goog[cert-manager/cert-manager-google-cas-issuer]"
  ]
}
