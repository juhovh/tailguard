#!/bin/sh

# Make sure Tailscale IPv4 packets are forwarded to WireGuard
iptables -C FORWARD -j ts-forward 2>/dev/null
if [ $? -ne 0 ]; then
  echo "The IPv4 firewall rules are not set up yet, failing healthcheck"
  exit 1
else
  iptables -C FORWARD -s 100.64.0.0/10 ! -o "${WG_DEVICE}" -j DROP 2>/dev/null
  if [ $? -eq 1 ]; then
    echo "Enforcing IPv4 firewall rules for tailscale packets"
    iptables -I FORWARD 1 -s 100.64.0.0/10 ! -o "${WG_DEVICE}" -j DROP
  fi
fi

# Make sure Tailscale IPv6 packets are forwarded to WireGuard
ip6tables -C FORWARD -j ts-forward 2>/dev/null
if [ $? -ne 0 ]; then
  echo "The IPv6 firewall rules are not set up yet, failing healthcheck"
  exit 1
else
  ip6tables -C FORWARD -s fd7a:115c:a1e0::/48 ! -o "${WG_DEVICE}" -j DROP 2>/dev/null
  if [ $? -eq 1 ]; then
    echo "Enforcing IPv6 firewall rules for tailscale packets"
    ip6tables -I FORWARD 1 -s fd7a:115c:a1e0::/48 ! -o "${WG_DEVICE}" -j DROP
  fi
fi
