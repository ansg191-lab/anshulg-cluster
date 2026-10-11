# Copyright (c) 2026. Anshul Gupta
# All rights reserved.

output "pki_int_csr" {
  description = "CSR for the Vault intermediate CA, to be signed by the Google Private CA root"
  value       = vault_pki_secret_backend_intermediate_cert_request.pki_int.csr
}
