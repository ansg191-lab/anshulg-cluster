# Copyright (c) 2026. Anshul Gupta
# All rights reserved.

variable "vault_addr" {
  description = "Public address of Vault, used for PKI AIA/CRL URLs"
  type        = string
  default     = "https://vault.anshulg.com"
}

# Google Private CA root that signs the Vault intermediate
variable "ca_location" {
  description = "Location of the Google Private CA pool"
  type        = string
}

variable "ca_pool_name" {
  description = "Name of the Google Private CA pool"
  type        = string
}

variable "ca_name" {
  description = "ID of the Google Private CA root certificate authority"
  type        = string
}
