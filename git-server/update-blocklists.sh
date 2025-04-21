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

init_table() {
	$NFT add table inet "$NFT_TABLE" || true
	$NFT add chain inet "$NFT_TABLE" "$NFT_CHAIN" '{ type filter hook input priority filter - 2; }' || true
}

contains_rule() {
	local name="$1"

	local json
	json=$($NFT -j list chain inet "$NFT_TABLE" "$NFT_CHAIN")

	echo "$json" | jq -e --arg blocklist "@$name" '
		.nftables[]
		| select(.rule != null)
		| .rule
		| select(.expr[]? | select(.match != null and .match.right == $blocklist))
	' > /dev/null
}

install_blocklist() {
	local blocklist_name="$1"
	local blocklist_url="https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/$blocklist_name.netset"

	# Download the blocklist
	local blocklist
	blocklist=$(curl --silent --fail --show-error --location "$blocklist_url")

	# Flush existing set if it exists
	$NFT flush set inet "$NFT_TABLE" "$blocklist_name" 2>/dev/null || true
	# Create the set
	$NFT add set inet "$NFT_TABLE" "$blocklist_name" "{ type ipv4_addr; flags interval; auto-merge; }" || true

	# Add rule to block ips in the set
	if ! contains_rule "$blocklist_name" ; then
		$NFT add rule inet "$NFT_TABLE" "$NFT_CHAIN" ip saddr "@$blocklist_name" drop
	fi

	# Filter out comments and empty lines, sort (removing duplicates), and paste into a single line delimited by commas
	elements=$(echo "$blocklist" | grep -Ev '^\s*($|#)' | sort -u | paste -sd, -)
	# Add the elements to the set
	echo "add element inet $NFT_TABLE $blocklist_name { $elements }" | $NFT -f -

}

init_table

for blocklist in "${BLOCKLISTS[@]}"; do
	install_blocklist "$blocklist"
done
