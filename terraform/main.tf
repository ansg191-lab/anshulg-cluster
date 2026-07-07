module "gcp" {
  source = "./modules/gcp"
}

module "vault" {
  source = "./modules/instance"

  role         = "vt"
  index        = 1
  machine_type = "n4a-standard-1"
  region       = "us-west1"
  zone         = "us-west1-c"

  boot_disk_os      = "debian-13-arm64"
  boot_disk_project = "debian-cloud"
  boot_disk_size_gb = 50
  boot_disk_type    = "hyperdisk-balanced"

  allowed_tcp_ports = [80, 443]
  allowed_udp_ports = [443]
  ssh_allowed_ips   = ["72.219.136.19/32"]

  create_service_account = true
}
