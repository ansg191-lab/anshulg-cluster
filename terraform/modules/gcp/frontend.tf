# DNS Zone data source for anshulg.com
# Used by auth.tf for DNS records
data "google_dns_managed_zone" "default" {
	name = var.dns_zone_anshulg_com
}
