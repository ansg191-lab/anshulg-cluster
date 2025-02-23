#!/usr/bin/env bash
#
# Copyright (c) 2025. Anshul Gupta
# All rights reserved.
#

set -eu

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

	# Handle providers
	if [[ "$provider" == "gcp" ]]; then
		gcloud dns record-sets import "$file" --zone="$zone" --zone-file-format --delete-all-existing
	else
		echo "File: '$file' | Unknown provider: '$provider'"
		continue
	fi

	echo "File: '$file' | Finished"
done
