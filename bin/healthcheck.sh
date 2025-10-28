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

iptables="iptables" CHAIN="INPUT" chain="input" update_firewall
iptables="iptables" CHAIN="FORWARD" chain="forward" update_firewall
iptables="iptables -t nat" CHAIN="POSTROUTING" chain="postrouting" update_firewall
iptables="ip6tables" CHAIN="INPUT" chain="input" update_firewall
iptables="ip6tables" CHAIN="FORWARD" chain="forward" update_firewall
iptables="ip6tables -t nat" CHAIN="POSTROUTING" chain="postrouting" update_firewall

# Add PREROUTING rules for TS_DEST_IP addresses if needed
for dest_ip in $(echo "${TS_DEST_IP}" | tr ',' '\n'); do
  tailscale_ipv4=$(tailscale ip -4 2>/dev/null)
  if [ -n "$tailscale_ipv4" ] && ipcalc -s -c -4 "$dest_ip"; then
    iptables -t nat -C PREROUTING -d $tailscale_ipv4 -j DNAT --to-destination $dest_ip 2>/dev/null
    if [ $? -ne 0 ]; then
      echo "Routing IPv4 address $tailscale_ipv4 to $dest_ip"
      iptables -t nat -A PREROUTING -d $tailscale_ipv4 -j DNAT --to-destination $dest_ip
    fi
  fi
  tailscale_ipv6=$(tailscale ip -6 2>/dev/null)
  if [ -n "$tailscale_ipv6" ] && ipcalc -s -c -6 "$dest_ip"; then
    ip6tables -t nat -C PREROUTING -d $tailscale_ipv6 -j DNAT --to-destination $dest_ip 2>/dev/null
    if [ $? -ne 0 ]; then
      echo "Routing IPv6 address $tailscale_ipv6 to $dest_ip"
      ip6tables -t nat -A PREROUTING -d $tailscale_ipv6 -j DNAT --to-destination $dest_ip
    fi
  fi
done

# Check Tailscale health using the health check endpoint
HEALTHZ_CODE="$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:9002/healthz")"
echo "Tailscale health endpoint returned response code: ${HEALTHZ_CODE}"
if [ $HEALTHZ_CODE != "200" ]; then exit 1; fi
