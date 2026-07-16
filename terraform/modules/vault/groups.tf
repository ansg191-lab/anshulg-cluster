# Copyright (c) 2026. Anshul Gupta
# All rights reserved.

resource "vault_identity_group" "vault_admins" {
  name     = "vault-admins"
  type     = "external"
  policies = ["tfc-policy"]
}

resource "vault_identity_entity_alias" "vault_admins_oidc" {
  name           = "idm_admins"
  mount_accessor = vault_jwt_auth_backend.oidc.accessor
  canonical_id   = vault_identity_group.vault_admins.id
}
