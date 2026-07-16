# ------------------------------------------------------------------------------
# TERRAFORM CLOUD AUTH
# ------------------------------------------------------------------------------

resource "vault_jwt_auth_backend" "tfc_jwt" {
  path               = "tfc_jwt"
  type               = "jwt"
  oidc_discovery_url = "https://app.terraform.io"
  bound_issuer       = "https://app.terraform.io"
}

resource "vault_jwt_auth_backend_role" "tfc_role" {
  backend                 = vault_jwt_auth_backend.tfc_jwt.path
  role_name               = "tfc-role"
  token_policies          = [vault_policy.tfc_policy.name]
  token_no_default_policy = true

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
    path         = "*"
    capabilities = ["create", "read", "update", "delete", "list", "sudo"]
    description  = "Allow token to manage everything"
  }
}

resource "vault_policy" "tfc_policy" {
  name   = "tfc-policy"
  policy = data.vault_policy_document.tfc_policy.hcl
}

# ------------------------------------------------------------------------------
# KANIDM OIDC AUTH
# ------------------------------------------------------------------------------

data "vault_kv_secret_v2" "oidc_config" {
  mount = vault_mount.kv_v2.path
  name  = "vault-oidc"
}

locals {
  client_id     = data.vault_kv_secret_v2.oidc_config.data["client_id"]
  client_secret = data.vault_kv_secret_v2.oidc_config.data["client_secret"]
  default_role  = "default"
}

resource "vault_jwt_auth_backend" "oidc" {
  type               = "oidc"
  path               = "oidc"
  description        = "KanIDM OIDC auth backend"
  oidc_discovery_url = "https://auth.anshulg.com/oauth2/openid/${local.client_id}"
  oidc_client_id     = local.client_id
  oidc_client_secret = local.client_secret
  default_role       = local.default_role

  tune {
    listing_visibility = "unauth"
  }
}

resource "vault_jwt_auth_backend_role" "oidc_default" {
  backend   = vault_jwt_auth_backend.oidc.path
  role_name = local.default_role
  role_type = "oidc"

  allowed_redirect_uris = [
    "https://vault.anshulg.com/ui/vault/auth/oidc/oidc/callback",
    "http://localhost:8250/oidc/callback"
  ]

  user_claim   = "preferred_username"
  groups_claim = "groups"

  oidc_scopes     = ["groups"]
  bound_audiences = [local.client_id]
}
