# Copyright (c) 2026. Anshul Gupta
# All rights reserved.

# ------------------------------------------------------------------------------
# PKI INTERMEDIATE CA
#
# Vault generates the intermediate key + CSR (key never leaves Vault), the
# Google Private CA root signs it, and the signed chain is imported back.
# ------------------------------------------------------------------------------

locals {
  pki_int_lifetime_seconds = 5 * 365 * 24 * 60 * 60 # 5 years
  pki_leaf_max_ttl_seconds = 365 * 24 * 60 * 60     # 1 year
}

resource "vault_mount" "pki_int" {
  path                      = "pki_int"
  type                      = "pki"
  description               = "Intermediate CA signed by Google Private CA root"
  default_lease_ttl_seconds = 30 * 24 * 60 * 60 # 30 days
  max_lease_ttl_seconds     = local.pki_leaf_max_ttl_seconds
}

resource "vault_pki_secret_backend_config_urls" "pki_int" {
  backend                 = vault_mount.pki_int.path
  issuing_certificates    = ["${var.vault_addr}/v1/${vault_mount.pki_int.path}/ca"]
  crl_distribution_points = ["${var.vault_addr}/v1/${vault_mount.pki_int.path}/crl"]
}

resource "vault_pki_secret_backend_intermediate_cert_request" "pki_int" {
  backend      = vault_mount.pki_int.path
  type         = "internal"
  common_name  = "Anshul Gupta Vault Intermediate CA"
  organization = "Anshul Gupta"
  province     = "California"
  country      = "US"
  key_type     = "ec"
  key_bits     = 384
}

# Forces CA basic constraints (pathlen 0) regardless of CSR contents, while
# letting the subject pass through from the CSR.
resource "google_privateca_certificate_template" "vault_intermediate" {
  name        = "vault-intermediate"
  location    = var.ca_location
  description = "Subordinate CA certificates for Vault PKI"

  maximum_lifetime = "${local.pki_int_lifetime_seconds}s"

  identity_constraints {
    allow_subject_passthrough           = true
    allow_subject_alt_names_passthrough = false
  }

  predefined_values {
    ca_options {
      is_ca                       = true
      zero_max_issuer_path_length = true
    }
    key_usage {
      base_key_usage {
        digital_signature = true
        cert_sign         = true
        crl_sign          = true
      }
      extended_key_usage {}
    }
  }
}

resource "google_privateca_certificate" "vault_intermediate" {
  name                  = "vault-intermediate"
  location              = var.ca_location
  pool                  = var.ca_pool_name
  certificate_authority = var.ca_name
  certificate_template  = google_privateca_certificate_template.vault_intermediate.id
  lifetime              = "${local.pki_int_lifetime_seconds}s"
  pem_csr               = vault_pki_secret_backend_intermediate_cert_request.pki_int.csr
}

resource "vault_pki_secret_backend_intermediate_set_signed" "pki_int" {
  backend = vault_mount.pki_int.path
  certificate = join("\n", concat(
    [google_privateca_certificate.vault_intermediate.pem_certificate],
    google_privateca_certificate.vault_intermediate.pem_certificate_chain,
  ))
}
