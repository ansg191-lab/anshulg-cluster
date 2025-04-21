#!/usr/bin/env bash
#
# Copyright (c) 2025. Anshul Gupta
# All rights reserved.
#
# This script downloads the following blocklists from iplists.firehol.org
# and adds them to nftables:
#   - ~firehol_level1~ (17 hours)
#		- Seems to cause DNS issues
#   - firehol_level2 (17 minutes)
#   - ~firehol_level3~ (1 hour 30 minutes)
#   - ~firehol_level4~ (14 minutes)


set -euo pipefail

declare -ar BLOCKLISTS=(
#	"firehol_level1"
	"firehol_level2"
)
declare -r NFT_TABLE="blocklist"
declare -r NFT_CHAIN="input"
declare -r NFT="/usr/sbin/nft"

# Check that we're root
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root" 1>&2
	exit 1
fi

# Check that nftables is installed
if ! command -v $NFT &> /dev/null; then
	echo "nftables could not be found. Please install it." 1>&2
	exit 1
fi

# Create NFT file for atomic updates
TABLE_FILE=$(mktemp)
CHAIN_FILE=$(mktemp)
trap '{ rm -f "$TABLE_FILE" "$CHAIN_FILE"; }' EXIT

# Initialize the table and chain
cat <<EOF > "$TABLE_FILE"
table inet $NFT_TABLE
flush table inet $NFT_TABLE
table inet $NFT_TABLE {
EOF
cat <<EOF >> "$CHAIN_FILE"
chain $NFT_CHAIN {
	type filter hook input priority filter - 2; policy accept;
EOF

install_blocklist() {
	local blocklist_name="$1"
	local blocklist_url="https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/$blocklist_name.netset"

	# Download the blocklist
	local blocklist
	blocklist=$(curl --silent --fail --show-error --location "$blocklist_url")

	# Add rule to block ips in the set
	echo "ip saddr @${blocklist_name} drop" >> "$CHAIN_FILE"

	# Filter out comments and empty lines, sort (removing duplicates), and paste into a single line delimited by commas
	elements=$(echo "$blocklist" | grep -Ev '^\s*($|#)' | sort -u | paste -sd, -)
	# Create set and add elements to it
	cat <<EOF >> "$TABLE_FILE"
set $blocklist_name {
	type ipv4_addr;
	flags interval;
	auto-merge;
	elements = { $elements }
}
EOF
}

for blocklist in "${BLOCKLISTS[@]}"; do
	install_blocklist "$blocklist"
done

echo "}" >> "$CHAIN_FILE"
cat "$CHAIN_FILE" >> "$TABLE_FILE"
echo "}" >> "$TABLE_FILE"

# Apply the changes
$NFT -f "$TABLE_FILE"
