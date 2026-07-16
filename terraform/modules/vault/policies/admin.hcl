# Allow access to Vault system endpoints
path "sys/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Allow access to Vault auth endpoints
path "auth/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Allow access to Vault identity endpoints
path "identity/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Allow access to kv store
path "kv/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
