resource "vault_jwt_auth_backend" "tfc_jwt" {
  path               = "tfc_jwt"
  type               = "jwt"
  oidc_discovery_url = "https://app.terraform.io"
  bound_issuer       = "https://app.terraform.io"
}

resource "vault_jwt_auth_backend_role" "tfc_role" {
  backend        = vault_jwt_auth_backend.tfc_jwt.path
  role_name      = "tfc-role"
  token_policies = [vault_policy.tfc_policy.name]

  bound_audiences   = ["vault.workload.identity"]
  bound_claims_type = "glob"
  bound_claims = {
    sub = "organization:ansg191:project:Default Project:workspace:anshulg-cluster:run_phase:*"
  }
  user_claim = "terraform_full_workspace"
  role_type  = "jwt"
  token_ttl  = 1200
}

data "vault_policy_document" "tfc_policy" {
  rule {
    path         = "auth/token/lookup-self"
    capabilities = ["read"]
    description  = "Allow tokens to query themselves"
  }
  rule {
    path         = "auth/token/renew-self"
    capabilities = ["update"]
    description  = "Allow tokens to renew themselves"
  }
  rule {
    path         = "auth/token/revoke-self"
    capabilities = ["update"]
    description  = "Allow tokens to revoke themselves"
  }

  rule {
    path         = "sys/*"
    capabilities = ["create", "read", "update", "delete", "list", "sudo"]
    description = "Allow token to manage vault"
  }
  rule {
    path         = "auth/*"
    capabilities = ["create", "read", "update", "delete", "list", "sudo"]
    description = "Allow token to manage vault auth"
  }
  rule {
    path         = "identity/*"
    capabilities = ["create", "read", "update", "delete", "list"]
    description = "Allow token to manage auth"
  }
}

resource "vault_policy" "tfc_policy" {
  name   = "tfc-policy"
  policy = data.vault_policy_document.tfc_policy.hcl
}

# Temporary import blocks
# import {
#   to = vault_jwt_auth_backend.tfc_jwt
#   id = "tfc_jwt"
# }
#
# import {
#   to = vault_jwt_auth_backend_role.tfc_role
#   id = "auth/tfc_jwt/role/tfc-role"
# }
#
# import {
#   to = vault_policy.tfc_policy
#   id = "tfc-policy"
# }
