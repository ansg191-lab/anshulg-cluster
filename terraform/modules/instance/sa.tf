# Copyright (c) 2026. Anshul Gupta
# All rights reserved.

resource "google_service_account" "this" {
  account_id   = local.hostname
  display_name = "${local.hostname} Service Account"
  description  = "Service account for ${local.hostname}"

  count = var.create_service_account ? 1 : 0
}
