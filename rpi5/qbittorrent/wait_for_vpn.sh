#!/usr/bin/env sh
#
# Copyright (c) 2026. Anshul Gupta
# All rights reserved.
#

echo "**** Waiting for VPN Connection ****"

for i in $(seq 1 60); do
	if ip addr show dev tun0 > /dev/null 2>&1; then
		echo "VPN is up, starting qBittorrent..."
		break
	else
		echo "Waiting for VPN to connect... ($i/60)"
		sleep 1
	fi
done

if ! ip addr show dev tun0 > /dev/null 2>&1; then
	echo "VPN connection failed to establish within the timeout period."
	exit 1
fi

IP_ADDR=$(curl -s https://icanhazip.com)
echo "Detected IP Address: $IP_ADDR"

echo "**** VPN Connection Established ****"
