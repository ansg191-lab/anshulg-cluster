# Copyright (c) 2026. Anshul Gupta
# All rights reserved.

# ------------------------------------------------------------------------------
# PKI INTERMEDIATE CA
#
# Vault generates the intermediate key + CSR (key never leaves Vault), the
# Google Private CA root signs it, and the signed chain is imported back.
#
# The root's pool is DEVOPS tier, which doesn't store issued certificates, so
# google_privateca_certificate can't be used (it 404s reading the cert back,
# see hashicorp/terraform-provider-google#14241). Signing is done by hand:
#
#   1. Apply, so Vault generates the CSR. set_signed is skipped while
#      pki_int.pem doesn't exist.
#
#   2. Fetch the CSR (from terraform/):
#
#        terraform output -raw vault_pki_int_csr > /tmp/pki_int.csr
#
#   3. Sign it with the root, writing the chain (leaf to root) next to this file:
#
#        gcloud privateca certificates create "vault-int-$(date +%Y%m%d)" \
#          --project=anshulg-cluster \
#          --issuer-pool=default --issuer-location=us-west1 \
#          --ca=anshul-ca-1 \
#          --template=vault-intermediate \
#          --csr=/tmp/pki_int.csr \
#          --validity=P1825D \
#          --cert-output-file=modules/vault/pki_int.pem
#
#   4. Check it, then commit pki_int.pem and apply:
#
#        openssl x509 -in modules/vault/pki_int.pem -noout -subject -enddate -ext basicConstraints
#
# Renewal: force a new CSR with
#   terraform apply -replace=module.vault_setup.vault_pki_secret_backend_intermediate_cert_request.pki_int
# then repeat steps 2-4, overwriting pki_int.pem. The new issuer becomes the
# default; the old one stays in Vault so certs it issued remain valid.
#
# The root expires 2033-08-05. Lower --validity for anything signed after
# 2028-08 so the intermediate doesn't outlive the root.
# ------------------------------------------------------------------------------

locals {
  pki_int_lifetime_seconds = 5 * 365 * 24 * 60 * 60 # 5 years
  pki_leaf_max_ttl_seconds = 365 * 24 * 60 * 60     # 1 year
  pki_int_cert_path        = "${path.module}/pki_int.pem"
}

resource "vault_mount" "pki_int" {
  path                      = "pki_int"
  type                      = "pki"
  description               = "Intermediate CA signed by Google Private CA root"
  default_lease_ttl_seconds = 30 * 24 * 60 * 60 # 30 days
  max_lease_ttl_seconds     = local.pki_leaf_max_ttl_seconds

  # Log non-sensitive PKI fields in plaintext so audit logs show what was
  # issued (keys suggested by `vault pki health-check`). private_key stays HMAC'd.
  audit_non_hmac_request_keys = [
    "csr", "certificate", "issuer_ref", "common_name", "alt_names", "other_sans",
    "ip_sans", "uri_sans", "ttl", "not_after", "serial_number", "key_type",
    "private_key_format", "managed_key_name", "managed_key_id", "ou",
    "organization", "country", "locality", "province", "street_address",
    "postal_code", "permitted_dns_domains", "policy_identifiers",
    "ext_key_usage_oids",
  ]
  audit_non_hmac_response_keys = [
    "certificate", "issuing_ca", "serial_number", "error", "ca_chain",
  ]

  # Lets clients fetch the CA/CRL only when they've changed
  passthrough_request_headers = ["If-Modified-Since"]
  allowed_response_headers    = ["Last-Modified"]
}

resource "vault_pki_secret_backend_config_auto_tidy" "pki_int" {
  backend            = vault_mount.pki_int.path
  enabled            = true
  interval_duration  = "12h"
  tidy_cert_store    = true
  tidy_revoked_certs = true

  tidy_revoked_cert_issuer_associations = true
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

# Signed by hand (see top of file), since the provider can't issue from a
# DEVOPS-tier pool. Skipped until the signed chain has been committed.
resource "vault_pki_secret_backend_intermediate_set_signed" "pki_int" {
  count = fileexists(local.pki_int_cert_path) ? 1 : 0

  backend     = vault_mount.pki_int.path
  certificate = fileexists(local.pki_int_cert_path) ? file(local.pki_int_cert_path) : ""
}

# Make the most recently imported intermediate the default issuer, so
# renewals take effect without manual issuer changes.
resource "vault_pki_secret_backend_config_issuers" "pki_int" {
  count = length(vault_pki_secret_backend_intermediate_set_signed.pki_int)

  backend = vault_mount.pki_int.path
  default = vault_pki_secret_backend_intermediate_set_signed.pki_int[0].imported_issuers[0]
}

# ------------------------------------------------------------------------------
# PKI ROLES
# ------------------------------------------------------------------------------

# Certs for embedded server devices (lacking auto-renewal)
resource "vault_pki_secret_backend_role" "embedded_server" {
  backend = vault_mount.pki_int.path
  name    = "embedded-server"
  ttl     = "8760h"
  max_ttl = "8760h"

  allow_localhost = false
  allowed_domains = [
    "anshulg.direct",
    "internal",
    "local",
  ]
  allow_bare_domains          = false
  allow_subdomains            = true
  allow_glob_domains          = false
  allow_wildcard_certificates = false
  allow_ip_sans               = true

  server_flag = true
  client_flag = false
  key_type    = "ec"
  key_bits    = 256

  key_usage = ["DigitalSignature"]

  country      = ["US"]
  province     = ["California"]
  organization = ["Anshul Gupta"]
}
