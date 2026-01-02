# Copyright (c) 2026. Anshul Gupta
# All rights reserved.

output "auth_static_ip" {
  description = "The static IP address of auth.anshulg.com"
  value = {
    ipv4 = module.gcp.kanidm_static_ip
    ipv6 = module.gcp.kanidm_static_ipv6
  }
}

output "service_accounts" {
  description = "Service account emails by purpose"
  value       = module.gcp.service_accounts
}

output "bucket_names" {
  description = "Storage bucket names by purpose"
  value       = module.gcp.bucket_names
}

output "bucket_urls" {
  description = "Storage bucket URLs"
  value       = module.gcp.bucket_urls
}
