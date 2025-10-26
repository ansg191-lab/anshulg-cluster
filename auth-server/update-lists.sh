#!/usr/bin/env bash
#
# Copyright (c) 2025. Anshul Gupta
# All rights reserved.
#

set -euo pipefail

IPSET_NAME="sshallowlist"
IPSET_TYPE="hash:net"
FIREWALL_ZONE="public"

OP_SERVICE_ACCOUNT_TOKEN=$(cat "1password.txt")
export OP_SERVICE_ACCOUNT_TOKEN

OP="/usr/local/bin/op"

IBLOCKLIST_USERNAME=$($OP read "op://auth.anshulg.com/I-Blocklist Download PIN/username")
IBLOCKLIST_PIN=$($OP read "op://auth.anshulg.com/I-Blocklist Download PIN/password")

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
	echo "Downloading GitHub IP ranges..."
    curl -fsSL "https://api.github.com/meta" | jq -r '.actions[] | select(test(":") | not)' >> "$TMPFILE"
}

function load_google() {
	echo "Downloading Google Cloud IP ranges..."
    curl -fsSL https://www.gstatic.com/ipranges/cloud.json | jq -r '.prefixes[] | select(.scope == "us-west2" and .ipv4Prefix != null) | .ipv4Prefix' >> "$TMPFILE"
}

function load_cox() {
	echo "Downloading Cox Communications IP ranges..."
    curl -fsSL "https://list.iblocklist.com/?list=nlgdvmvfxvoimdunmuju&fileformat=cidr&archiveformat=&username=$IBLOCKLIST_USERNAME&pin=$IBLOCKLIST_PIN" >> "$TMPFILE"
}

function load_charter() {
	echo "Downloading Charter Communications IP ranges..."
	curl -fsSL "https://list.iblocklist.com/?list=htnzojgossawhpkbulqw&fileformat=cidr&archiveformat=&username=$IBLOCKLIST_USERNAME&pin=$IBLOCKLIST_PIN" >> "$TMPFILE"
}

function load_cidr() {
	echo "Loading custom CIDR ranges..."
	cat /home/anshulgupta/cidr.txt >> "$TMPFILE"
}

function filter_cidr() {
	local f=$1
	echo "Filtering CIDR ranges from $f ..."
	python3 - "$f" << 'PY'
import sys, ipaddress, tempfile, os, re
with open(sys.argv[1]) as fh:
    raw = [l.strip() for l in fh if l.strip() and not re.match(r'^[#;]', l.strip())]
nets = [ipaddress.ip_network(l) for l in raw]
# sort by prefix length (ascending = largest blocks first), then by address
nets.sort(key=lambda n: (n.prefixlen, n.network_address))
out = []
for cand in nets:
    if not any(cand.subnet_of(existing) for existing in out):
        out.append(cand)
with tempfile.NamedTemporaryFile(mode='w', delete=False) as tf:
    tf.write('\n'.join(str(n) for n in out) + '\n')
    os.replace(tf.name, sys.argv[1])
PY
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
load_google
load_cox
load_charter
load_cidr
filter_cidr "$TMPFILE"

echo "Creating IP set and adding firewall rules..."
echo "Total entries: $(wc -l < "$TMPFILE")"

create_ipset
add_rule
