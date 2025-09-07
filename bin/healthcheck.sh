#!/bin/sh

# Make sure Tailscale IPv4 packets are forwarded to WireGuard
iptables -C FORWARD -j ts-forward 2>/dev/null
if [ $? -ne 0 ]; then
  echo "The IPv4 firewall rules are not set up yet for, failing healthcheck"
  exit 1
else
  iptables -C FORWARD -j tg-forward 2>/dev/null
  if [ $? -ne 0 ]; then
    echo "Enforcing IPv4 firewall rules"
    iptables -I FORWARD 1 -j tg-forward
  fi
fi

# Make sure Tailscale IPv6 packets are forwarded to WireGuard
ip6tables -C FORWARD -j ts-forward 2>/dev/null
if [ $? -ne 0 ]; then
  echo "The IPv6 firewall rules are not set up yet, failing healthcheck"
  exit 1
else
  ip6tables -C FORWARD -j tg-forward 2>/dev/null
  if [ $? -ne 0 ]; then
    echo "Enforcing IPv6 firewall rules"
    ip6tables -I FORWARD 1 -j tg-forward
  fi
fi

# Check Tailscale health using the health check endpoint
HEALTHZ_CODE="$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:9002/healthz")"
echo "Tailscale health endpoint returned response code: ${HEALTHZ_CODE}"
if [ $HEALTHZ_CODE != "200" ]; then exit 1; fi
