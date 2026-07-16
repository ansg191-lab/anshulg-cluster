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
