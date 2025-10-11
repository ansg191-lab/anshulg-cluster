#!/usr/bin/env sh
#
# Copyright (c) 2025. Anshul Gupta
# All rights reserved.
#

set -e

echo "Installing OpenVPN and dependencies..."
apt-get update && apt-get install -y --no-install-recommends openvpn iproute2 iptables ca-certificates

# Create authentication file
echo "Setting up OpenVPN credentials..."
if [ -f /auth/username ] && [ -f /auth/password ]; then
	printf "%s\n%s\n" "$(cat /auth/username)" "$(cat /auth/password)" > /credentials
	chmod 600 /credentials
fi

# Start OpenVPN
echo "Starting OpenVPN..."
openvpn --config /config/client.ovpn --pull --script-security 2 --daemon

# Wait for tun0 to appear
echo "Waiting for tun0 interface..."
for _i in $(seq 1 60); do
	ip link show tun0 >/dev/null 2>&1 && break
	sleep 1
done
ip link show tun0 >/dev/null 2>&1 || { echo "tun0 not up"; exit 1; }

# Basic leak protection: drop outbound if not via tun0 (allow established & DNS as needed)
echo "Starting leak protection..."
iptables -P OUTPUT DROP
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
# Allow DNS to VPN DNS (pushed) will be covered by ESTABLISHED; allow cluster DNS if needed:
iptables -A OUTPUT -d "$CLUSTER_DNS_IP" -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -d "$CLUSTER_DNS_IP" -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -o tun0 -j ACCEPT

# Allow traffic to k8s internal services
ip route add 10.43.0.0/16 via 10.42.0.1 dev eth0

# Keep the container alive and expose logs if OpenVPN dies
echo "Container setup complete. Running forever..."
tail -F /var/log/* /dev/null
