#!/bin/bash

set -euxo pipefail

# Delete firewall rules
iptables -D INPUT -j WG-INPUT || true
iptables -F WG-INPUT || true
iptables -X WG-INPUT || true
iptables -F WG-INPUT-INTERNAL || true
iptables -X WG-INPUT-INTERNAL || true

ip6tables -D INPUT -j WG-INPUT || true
ip6tables -F WG-INPUT || true
ip6tables -X WG-INPUT || true
ip6tables -F WG-INPUT-INTERNAL || true
ip6tables -X WG-INPUT-INTERNAL || true

# Delete routes
ip route del 192.168.0.0/22 dev wg0 || true
ip route del fd30:e1bf:9b4f::/48 dev wg0 || true

# Delete wireguard link
ip link set down dev wg0 || true
ip link del dev wg0 || true
