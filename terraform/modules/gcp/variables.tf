# Project Configuration
variable "project_id" {
  description = "The GCP project ID"
  type        = string
  default     = "anshulg-cluster"
}

# Regional Configuration
variable "primary_region" {
  description = "Primary GCP region for most resources"
  type        = string
  default     = "us-west1"
}

variable "auth_region" {
  description = "Region for auth server"
  type        = string
  default     = "us-west2"
}

variable "auth_zone" {
  description = "Zone for auth server"
  type        = string
  default     = "us-west2-b"
}

# Private CA Configuration
variable "ca_pool_name" {
  description = "Name of the Private CA pool"
  type        = string
  default     = "default"
}

variable "ca_pool_tier" {
  description = "Tier of the Private CA pool (DEVOPS or ENTERPRISE)"
  type        = string
  default     = "DEVOPS"
}

variable "ca_name" {
  description = "Name of the Certificate Authority"
  type        = string
  default     = "anshul-ca-1"
}

# KanIDM Instance Configuration
variable "kanidm_machine_type" {
  description = "Machine type for KanIDM instance"
  type        = string
  default     = "n1-standard-1"
}

variable "kanidm_disk_size" {
  description = "Boot disk size for KanIDM instance in GB"
  type        = number
  default     = 20
}

variable "kanidm_disk_type" {
  description = "Boot disk type for KanIDM instance"
  type        = string
  default     = "pd-balanced"
}

variable "kanidm_image" {
  description = "OS image for KanIDM instance"
  type        = string
  default     = "projects/opensuse-cloud/global/images/opensuse-leap-15-6-v20251017-x86-64"
}

variable "kanidm_ssh_allowed_ips" {
  description = "IP ranges allowed to SSH to KanIDM instance"
  type        = list(string)
  default = [
    "72.219.136.19/32", # Cox ISP
    "169.235.0.0/16",   # UCR network
    "96.41.17.70/32",   # Spectrum ISP
  ]
}

variable "kanidm_backup_retention_days" {
  description = "Number of days to retain KanIDM snapshots"
  type        = number
  default     = 7
}

# Storage Configuration
variable "restic_bucket_name" {
  description = "Name of the restic backup bucket"
  type        = string
  default     = "restic-backup-bucket-9r6c"
}

variable "debian_apt_bucket_name" {
  description = "Name of the Debian APT repository bucket"
  type        = string
  default     = "anshulg-debian-apt"
}

variable "bucket_location" {
  description = "Location for storage buckets"
  type        = string
  default     = "US"
}

variable "bucket_storage_class" {
  description = "Storage class for buckets"
  type        = string
  default     = "STANDARD"
}

# DNS Configuration
variable "dns_zone_anshulg_com" {
  description = "Name of the anshulg.com managed zone"
  type        = string
  default     = "anshulg-com"
}

variable "dns_zone_anshulg_direct" {
  description = "Name of the anshulg.direct managed zone"
  type        = string
  default     = "anshulg-direct"
}

# Resource Labels
variable "common_labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    managed_by = "terraform"
    project    = "anshulg-cluster"
  }
}
