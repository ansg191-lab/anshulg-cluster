# Copyright (c) 2026. Anshul Gupta
# All rights reserved.

# region Identity

# variable "name" {
#   description = "Name of the instance"
#   type        = string
# }

variable "role" {
  description = "2-char role"
  type        = string
  validation {
    condition     = length(var.role) == 2
    error_message = "Role must be 2 characters long"
  }
}

variable "index" {
  description = "Index, unique within role. Zero-padded to 2 digits (0-99)"
  type        = number
  validation {
    condition     = var.index >= 0 && var.index <= 99
    error_message = "Index must be between 0 and 99"
  }
}

variable "machine_type" {
  description = "Machine type for the instance"
  type        = string
}

variable "region" {
  description = "Region for the instance"
  type        = string
}

variable "zone" {
  description = "Zone for the instance"
  type        = string
}

# endregion Identity

# region Boot Disk

variable "boot_disk_os" {
  description = "Operating system for the boot disk"
  type        = string
}

variable "boot_disk_project" {
  description = "Project the OS is hosted in. Ex: debian-cloud"
  type        = string
}

variable "boot_disk_size_gb" {
  description = "Size of the boot disk in GB"
  type        = number
}

variable "boot_disk_type" {
  description = "Type of the boot disk"
  type        = string
}

# endregion Boot Disk

# region Environment

variable "domain" {
  description = "Domain name"
  type        = string
  default     = "anshulg.com"
}

# endregion Environment

variable "create_service_account" {
  description = "Whether to create a service account for the instance"
  type        = bool
  default     = false
}

# region Firewall

variable "allowed_tcp_ports" {
  description = "TCP ports to allow inbound from anywhere (IPv4)."
  type        = list(number)
  default     = []
}

variable "allowed_udp_ports" {
  description = "UDP ports to allow inbound from anywhere (IPv4)."
  type        = list(number)
  default     = []
}

variable "ssh_allowed_ips" {
  description = "IP ranges allowed to SSH (port 22)"
  type        = list(string)
  default     = []
}

# endregion Firewall
