#!/bin/bash

set -euxo pipefail

# Delete routes
ip route del 192.168.0.0/22 dev wg0 || true
ip route del fd30:e1bf:9b4f::/48 dev wg0 || true

# Delete wireguard link
ip link set down dev wg0 || true
ip link del dev wg0 || true
