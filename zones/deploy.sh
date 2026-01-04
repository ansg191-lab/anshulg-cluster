#!/usr/bin/env bash
#
# Copyright (c) 2026. Anshul Gupta
# All rights reserved.
#

set -eu

# Ensure we're in the zones directory
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

# Get all zonefiles in `zones`
for file in *.zonefile; do
	[ -e "$file" ] || continue

	# Get header
	header=$(head -n 1 "$file")

	# Extract provider and zone
	if [[ $header =~ "; provider="(.*)" zone="(.*)"" ]]; then
		provider=${BASH_REMATCH[1]}
		zone=${BASH_REMATCH[2]}
	else
		echo "File: '$file' | No header found"
		continue
	fi

	if [[ -z "$provider" || -z "$zone" ]]; then
		echo "File: '$file' | Invalid header (empty provider or zone)"
		continue
	fi

	# Handle providers
	if [[ "$provider" == "gcp" ]]; then
		echo "File: '$file' | Deploying to GCP zone: $zone"
		if gcloud dns record-sets import "$file" --zone="$zone" --zone-file-format --delete-all-existing; then
			echo "File: '$file' | Finished successfully"
		else
			echo "File: '$file' | ERROR: Failed to import DNS records" >&2
			exit 1
		fi
	else
		echo "File: '$file' | Unknown provider: '$provider'"
		continue
	fi
done
