data "google_dns_managed_zone" "default" {
	name = "anshulg-com"
}

resource "google_compute_ssl_policy" "ssl-policy" {
	name            = "k8s-ssl-policy"
	profile         = "RESTRICTED"
	min_tls_version = "TLS_1_2"
}

resource "google_certificate_manager_certificate" "default" {
	name        = "default"
	description = "The default certificate"
	location    = "global"
	scope       = "DEFAULT"
	managed {
		domains = [
			google_certificate_manager_dns_authorization.base.domain,
			"*.${google_certificate_manager_dns_authorization.base.domain}"
		]
		dns_authorizations = [
			google_certificate_manager_dns_authorization.base.id
		]
	}
}

resource "google_certificate_manager_dns_authorization" "base" {
	name   = "anshulg-base"
	domain = "anshulg.com"
}

resource "google_dns_record_set" "cert-cname" {
	name         = google_certificate_manager_dns_authorization.base.dns_resource_record[0].name
	managed_zone = data.google_dns_managed_zone.default.name
	type         = google_certificate_manager_dns_authorization.base.dns_resource_record[0].type
	ttl          = 300
	rrdatas      = [google_certificate_manager_dns_authorization.base.dns_resource_record[0].data]
}

resource "google_certificate_manager_certificate_map" "default" {
	name = "anshulg-map"
}

resource "google_certificate_manager_certificate_map_entry" "default" {
	name         = "anshulg-base-map-entry"
	certificates = [google_certificate_manager_certificate.default.id]
	map          = google_certificate_manager_certificate_map.default.name
	matcher      = "PRIMARY"
}

# Backend Service

resource "google_compute_global_network_endpoint_group" "k8s" {
	name                  = "k8s"
	network_endpoint_type = "INTERNET_IP_PORT"
	default_port          = 443
}

resource "google_compute_global_network_endpoint" "k8s" {
	global_network_endpoint_group = google_compute_global_network_endpoint_group.k8s.id
	port                          = google_compute_global_network_endpoint_group.k8s.default_port
	ip_address                    = "35.199.156.70"
}

resource "google_compute_backend_service" "k8s-lb" {
	name     = "k8s-backend"
	protocol = "HTTPS"

	compression_mode = "AUTOMATIC"
	enable_cdn       = true
	cdn_policy {
		cache_mode                   = "CACHE_ALL_STATIC"
	}

	custom_response_headers = [
		"X-Cache-Hit: {cdn_cache_status}"
	]

	#	log_config {
	#		enable      = true
	#		sample_rate = 1
	#	}

	iap {
		enabled = false
	}

	backend {
		group = google_compute_global_network_endpoint_group.k8s.id
	}

	timeout_sec = 1800
	connection_draining_timeout_sec = 1800
}

resource "google_compute_url_map" "default" {
	name            = "k8s-frontend"
	default_service = google_compute_backend_service.k8s-lb.id
}

resource "google_compute_url_map" "ssl-redirect" {
	name = "k8s-ssl-redirect"
	default_url_redirect {
		https_redirect = true
		strip_query    = false
	}
}

# IPv4

resource "google_compute_global_address" "ipv4" {
	name         = "frontend-ipv4"
	address_type = "EXTERNAL"
	ip_version   = "IPV4"
}

resource "google_compute_target_https_proxy" "ipv4-https" {
	name            = "ipv4-https"
	url_map         = google_compute_url_map.default.id
	certificate_map = "//certificatemanager.googleapis.com/${google_certificate_manager_certificate_map.default.id}"
	ssl_policy      = google_compute_ssl_policy.ssl-policy.id
	quic_override   = "ENABLE"
}

resource "google_compute_global_forwarding_rule" "ipv4-https" {
	name        = "ipv4-https"
	ip_protocol = "TCP"
	port_range  = "443"
	target      = google_compute_target_https_proxy.ipv4-https.id
	ip_address  = google_compute_global_address.ipv4.id
}

resource "google_compute_target_http_proxy" "ipv4-http" {
	name    = "ipv4-http"
	url_map = google_compute_url_map.ssl-redirect.id
}

resource "google_compute_global_forwarding_rule" "ipv4-http" {
	name        = "ipv4-http"
	ip_protocol = "TCP"
	port_range  = "80"
	target      = google_compute_target_http_proxy.ipv4-http.id
	ip_address  = google_compute_global_address.ipv4.id
}

# IPv6

resource "google_compute_global_address" "ipv6" {
	name         = "frontend-ipv6"
	address_type = "EXTERNAL"
	ip_version   = "IPV6"
}

resource "google_compute_target_https_proxy" "ipv6-https" {
	name            = "ipv6-https"
	url_map         = google_compute_url_map.default.id
	certificate_map = "//certificatemanager.googleapis.com/${google_certificate_manager_certificate_map.default.id}"
	ssl_policy      = google_compute_ssl_policy.ssl-policy.id
	quic_override   = "ENABLE"
}

resource "google_compute_global_forwarding_rule" "ipv6-https" {
	name        = "ipv6-https"
	ip_protocol = "TCP"
	port_range  = "443"
	target      = google_compute_target_https_proxy.ipv6-https.id
	ip_address  = google_compute_global_address.ipv6.id
}

resource "google_compute_target_http_proxy" "ipv6-http" {
	name    = "ipv6-http"
	url_map = google_compute_url_map.ssl-redirect.id
}

resource "google_compute_global_forwarding_rule" "ipv6-http" {
	name        = "ipv6-http"
	ip_protocol = "TCP"
	port_range  = "80"
	target      = google_compute_target_http_proxy.ipv6-http.id
	ip_address  = google_compute_global_address.ipv6.id
}

# DNS Records

resource "google_dns_record_set" "ipv4-base" {
	managed_zone = data.google_dns_managed_zone.default.name
	name         = data.google_dns_managed_zone.default.dns_name
	type         = "A"
	ttl          = 86400
	rrdatas      = [
		google_compute_global_address.ipv4.address
	]
}

resource "google_dns_record_set" "ipv4-wildcard" {
	managed_zone = data.google_dns_managed_zone.default.name
	name         = "*.${data.google_dns_managed_zone.default.dns_name}"
	type         = "A"
	ttl          = 86400
	rrdatas      = [
		google_compute_global_address.ipv4.address
	]
}

resource "google_dns_record_set" "ipv6-base" {
	managed_zone = data.google_dns_managed_zone.default.name
	name         = data.google_dns_managed_zone.default.dns_name
	type         = "AAAA"
	ttl          = 86400
	rrdatas      = [
		google_compute_global_address.ipv6.address
	]
}

resource "google_dns_record_set" "ipv6-wildcard" {
	managed_zone = data.google_dns_managed_zone.default.name
	name         = "*.${data.google_dns_managed_zone.default.dns_name}"
	type         = "AAAA"
	ttl          = 86400
	rrdatas      = [
		google_compute_global_address.ipv6.address
	]
}

# HTTPS DNS Records
resource "google_dns_record_set" "base-https" {
	managed_zone = data.google_dns_managed_zone.default.name
	name         = data.google_dns_managed_zone.default.dns_name
	type         = "HTTPS"
	ttl          = 86400
	rrdatas      = [
		"1 . alpn=\"h3,h2\""
	]
}

resource "google_dns_record_set" "wildcard-https" {
	managed_zone = data.google_dns_managed_zone.default.name
	name         = "*.${data.google_dns_managed_zone.default.dns_name}"
	type         = "HTTPS"
	ttl          = 86400
	rrdatas      = [
		"1 . alpn=\"h3,h2\""
	]
}
