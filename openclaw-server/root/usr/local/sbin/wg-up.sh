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

################################################################################
# Firewall rules
################################################################################
iptables -N WG-INPUT

# Allow loopback & ICMP
iptables -A WG-INPUT -i lo -j ACCEPT
iptables -A WG-INPUT -p icmp -j ACCEPT

# Allow conntrack
iptables -A WG-INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow WireGuard traffic
iptables -A WG-INPUT -p udp --dport 51820 -j ACCEPT

# Allow SSH traffic
iptables -A WG-INPUT -p tcp --dport 22 -j ACCEPT

# Allow DHCP traffic
iptables -A WG-INPUT -p udp --dport 67:68 --sport 67:68 -j ACCEPT

# Delegate wireguard traffic
iptables -N WG-INPUT-INTERNAL
iptables -A WG-INPUT -i wg0 -j WG-INPUT-INTERNAL

# Drop everything else
iptables -A WG-INPUT -j DROP

# Allow internal traffic (SSH, HTTP, HTTPS)
iptables -A WG-INPUT-INTERNAL -p tcp --dport 22 -j ACCEPT
iptables -A WG-INPUT-INTERNAL -p tcp --dport 80 -j ACCEPT
iptables -A WG-INPUT-INTERNAL -p tcp --dport 443 -j ACCEPT
iptables -A WG-INPUT-INTERNAL -p udp --dport 443 -j ACCEPT

# Attach the chain to the INPUT chain
iptables -A INPUT -j WG-INPUT

################################################################################
# IPV6 Firewall rules
################################################################################
ip6tables -N WG-INPUT

# Allow loopback & ICMP
ip6tables -A WG-INPUT -i lo -j ACCEPT
ip6tables -A WG-INPUT -p icmpv6 -j ACCEPT

# Allow conntrack
ip6tables -A WG-INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow WireGuard traffic
ip6tables -A WG-INPUT -p udp --dport 51820 -j ACCEPT

# Allow SSH traffic
ip6tables -A WG-INPUT -p tcp --dport 22 -j ACCEPT

# Allow DHCP traffic
ip6tables -A WG-INPUT -p udp --dport 67:68 --sport 67:68 -j ACCEPT

# Delegate wireguard traffic
ip6tables -N WG-INPUT-INTERNAL
ip6tables -A WG-INPUT -i wg0 -j WG-INPUT-INTERNAL

# Drop everything else
ip6tables -A WG-INPUT -j DROP

# Allow internal traffic (SSH, HTTP, HTTPS)
ip6tables -A WG-INPUT-INTERNAL -p tcp --dport 22 -j ACCEPT
ip6tables -A WG-INPUT-INTERNAL -p tcp --dport 80 -j ACCEPT
ip6tables -A WG-INPUT-INTERNAL -p tcp --dport 443 -j ACCEPT
ip6tables -A WG-INPUT-INTERNAL -p udp --dport 443 -j ACCEPT

# Attach the chain to the INPUT chain
ip6tables -I INPUT 1 -j WG-INPUT
