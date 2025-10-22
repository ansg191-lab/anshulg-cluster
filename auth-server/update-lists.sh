#!/usr/bin/env bash
#
# Copyright (c) 2025. Anshul Gupta
# All rights reserved.
#

set -euo pipefail

IPSET_NAME="sshallowlist"
IPSET_TYPE="hash:net"
FIREWALL_ZONE="public"

TMPFILE=$(mktemp)

function cleanup() {
	rm "$TMPFILE"
}

function assert_sudo() {
	if [ "$EUID" -ne 0 ]; then
		echo "Please run as root"
		exit 1
	fi
}

function load_github() {
    curl -fsSL "https://api.github.com/meta" | jq -r '.actions[] | select(test(":") | not)' >> "$TMPFILE"
}

function load_cidr() {
	cat /home/anshulgupta/cidr.txt >> "$TMPFILE"
}

function create_ipset() {
	if firewall-cmd --permanent --get-ipsets | grep -q "^$IPSET_NAME$"; then
        firewall-cmd --permanent --delete-ipset="$IPSET_NAME"
    fi
    firewall-cmd --permanent --new-ipset="$IPSET_NAME" --type="$IPSET_TYPE" --option=family=inet --option=hashsize=16384 --option=maxelem=20000

    firewall-cmd --permanent --ipset="$IPSET_NAME" --add-entries-from-file="$TMPFILE"
}

function add_rule() {
    if firewall-cmd --permanent --zone="$FIREWALL_ZONE" --query-service=ssh &>/dev/null; then
        firewall-cmd --permanent --zone="$FIREWALL_ZONE" --remove-service=ssh
    fi

	if ! firewall-cmd --permanent --zone="$FIREWALL_ZONE" --query-rich-rule="rule source ipset=\"$IPSET_NAME\" service name=\"ssh\" accept" &>/dev/null; then
        firewall-cmd --permanent --zone="$FIREWALL_ZONE" --add-rich-rule="rule source ipset=\"$IPSET_NAME\" service name=\"ssh\" accept"
    fi

    firewall-cmd --reload
}

trap cleanup EXIT
assert_sudo
load_github
load_cidr
create_ipset
add_rule
