#!/bin/bash
set -euxo pipefail

if ip link show wg0 >/dev/null 2>&1; then
  echo "wg0 already exists, nothing to do."
  exit 0
fi

# Setup Wireguard
ip link add dev wg0 type wireguard
sleep 1

wg setconf wg0 /etc/wireguard/wg0.conf
ip link set mtu 1280 dev wg0
ip addr add 192.168.3.5/24 dev wg0
ip addr add fd30:e1bf:9b4f:100::5/64 dev wg0
ip link set up dev wg0

# Add routes (replace with OSPF in the future)
ip route add 192.168.0.0/22 dev wg0
ip route add fd30:e1bf:9b4f::/48 dev wg0

# Split DNS: resolve *.internal through the tunnel
resolvectl dns wg0 192.168.3.1
resolvectl domain wg0 "~internal"
