#!/bin/sh

update_firewall() {
  $iptables -C $CHAIN -j "ts-$chain" 2>/dev/null
  if [ $? -ne 0 ]; then
    echo "The $iptables ts-$chain rules are not set up yet, failing healthcheck"
    exit 1
  fi
  $iptables -C $CHAIN -j "tg-$chain" 2>/dev/null
  if [ $? -ne 0 ]; then
    echo "Enforcing $iptables tg-$chain rules"
    $iptables -I $CHAIN 1 -j "tg-$chain"
  fi
}

iptables="iptables" CHAIN="INPUT" chain="input"; update_firewall
iptables="iptables" CHAIN="FORWARD" chain="forward"; update_firewall
iptables="iptables -t nat" CHAIN="POSTROUTING" chain="postrouting"; update_firewall
iptables="ip6tables" CHAIN="INPUT" chain="input"; update_firewall
iptables="ip6tables" CHAIN="FORWARD" chain="forward"; update_firewall
iptables="ip6tables -t nat" CHAIN="POSTROUTING" chain="postrouting"; update_firewall

# Check Tailscale health using the health check endpoint
HEALTHZ_CODE="$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:9002/healthz")"
echo "Tailscale health endpoint returned response code: ${HEALTHZ_CODE}"
if [ $HEALTHZ_CODE != "200" ]; then exit 1; fi
