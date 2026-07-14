# Copyright (c) 2026. Anshul Gupta
# All rights reserved.

# KV V2 mount
resource "vault_mount" "kv_v2" {
  path        = "kv"
  type        = "kv-v2"
  description = "KV V2 mount"
}
