#!/usr/bin/env bash
#
# Copyright (c) 2025. Anshul Gupta
# All rights reserved.
#

set -Eeuo pipefail

trap 'echo "Error on line $LINENO"; exit 1' ERR

DOMAINS_STR="${DOMAINS:-gupta-vpn anshul-vpn}"
read -r -a DOMAINS <<< "$DOMAINS_STR"
TOKEN="${TOKEN:-}"

################################################################################
# FUNCTIONS
################################################################################

err() { echo "ERROR: $*" >&2; exit 1; }

get_ipv4() {
	ip="$(curl -4fsS https://api.ipify.org || true)"
	if [[ -z "${ip}" ]]; then
	  ip="$(curl -4fsS https://ifconfig.me/ip || true)"
	fi
	if [[ -z "${ip}" ]]; then
	  ip="$(curl -4fsS https://checkip.amazonaws.com || true)"
	fi
	[[ "${ip}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || err "Could not determine public IPv4 (got: '${ip}')"
	echo "${ip}"
}

get_ipv6() {
	INTERFACE="$(ip -6 route list default | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"

	ip -6 addr show dev "$INTERFACE" scope global \
		| grep inet6 \
		| grep -Ev 'deprecated|temporary' \
		| awk '$2 !~ /^f(d|c)/ { print $2 }' \
		| cut -d/ -f1
}

duckdns_update() {
	local domain="$1"
	local ipv4="$2"
	local ipv6="$3"
	local verbose="${4:-false}"

	local url="https://www.duckdns.org/update?domains=${domain}&token=${TOKEN}"
	[[ -n "${ipv4}" ]] && url+="&ip=${ipv4}"
	[[ -n "${ipv6}" ]] && url+="&ipv6=${ipv6}"
	[[ "${verbose}" == "true" ]] && url+="&verbose=true"

	local tmp status
	tmp="$(mktemp)"
	status="$(curl -sS -o "$tmp" -w '%{http_code}' "$url")"
	if [[ "${status}" != "200" ]]; then
		echo "DuckDNS API error: Update for domain '${domain}' -> HTTP ${status}" >&2
		cat "$tmp" >&2
		echo
		rm -f "$tmp"
		exit 1
	fi
	if grep -q "KO" "$tmp"; then
		echo "DuckDNS API error: Update for domain '${domain}'" >&2
		cat "$tmp" >&2
		echo
		rm -f "$tmp"
		exit 1
	fi

	cat "$tmp"
	rm -f "$tmp"
}

################################################################################
# MAIN
################################################################################

[[ -n "${TOKEN}" ]] || err "TOKEN is empty"

IPV4="$(get_ipv4)"
IPV6="$(get_ipv6)"
#IPV6="2600:8802:1900:a3:1cc6:e5de:58b2:53de"

[[ -n "${IPV4}" ]] || err "Could not determine public IPv4"
[[ -n "${IPV6}" ]] || err "Could not determine public IPv6"
echo "Public IPv4:     ${IPV4}"
echo "Public IPv6:     ${IPV6}"
echo

# For each domain, update both A and AAAA records
for domain in "${DOMAINS[@]}"; do
	echo "Updating Domain: ${domain}.duckdns.org"

	duckdns_update "${domain}" "${IPV4}" "${IPV6}" "true"
	printf "\n\n"
done
