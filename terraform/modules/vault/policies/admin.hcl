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

# Allow access to transit
path "transit/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Allow access to database
path "database/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Allow access to ssh-client-signer
path "ssh-client-signer/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Allow access to ssh-host-signer
path "ssh-host-signer/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
