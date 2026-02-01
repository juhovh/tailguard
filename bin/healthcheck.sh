#!/bin/sh

# This is a path to execute scripts on a healthy Tailscale, 
# must be the same path as set in entrypoint.sh
DELAYED_SCRIPT_PATH="/tailguard/.delayed-script.sh"
HEALTHY_EPOCH_PATH="/tailguard/.healthy-epoch"

update_firewall() {
  if ! $iptables -C $CHAIN -j "ts-$chain" 2>/dev/null; then
    echo "The $iptables ts-$chain rules are not set up yet, failing healthcheck"
    exit 1
  fi
  if ! $iptables -C $CHAIN -j "tg-$chain" 2>/dev/null; then
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
  if tailscale_ipv4="$(tailscale ip -4 2>/dev/null)" && ipcalc -s -c -4 "$dest_ip"; then
    if ! iptables -t nat -C PREROUTING -d $tailscale_ipv4 -j DNAT --to-destination $dest_ip 2>/dev/null; then
      echo "Forwarding Tailscale IPv4 address $tailscale_ipv4 to $dest_ip"
      iptables -t nat -A PREROUTING -d $tailscale_ipv4 -j DNAT --to-destination $dest_ip
    fi
  fi
  if tailscale_ipv6="$(tailscale ip -6 2>/dev/null)" && ipcalc -s -c -6 "$dest_ip"; then
    if ! ip6tables -t nat -C PREROUTING -d $tailscale_ipv6 -j DNAT --to-destination $dest_ip 2>/dev/null; then
      echo "Forwarding Tailscale IPv6 address $tailscale_ipv6 to $dest_ip"
      ip6tables -t nat -A PREROUTING -d $tailscale_ipv6 -j DNAT --to-destination $dest_ip
    fi
  fi
done

# Check Tailscale health using the health check endpoint
HEALTHZ_CODE="$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:9002/healthz")"
echo "Tailscale health endpoint returned response code: ${HEALTHZ_CODE}"
if [ $HEALTHZ_CODE != "200" ]; then
  # The system is not healthy, delete epoch if present
  rm -f "${HEALTHY_EPOCH_PATH}"
  exit 1
fi

# Record the healthy epoch to file for reference
if [ ! -f "${HEALTHY_EPOCH_PATH}" ]; then
  echo "$(date +%s)" > "${HEALTHY_EPOCH_PATH}"
fi

# Run delayed script if present, generally created by entrypoint.sh
if [ -f "${DELAYED_SCRIPT_PATH}" ]; then
  DELAYED_SCRIPT=$(cat "${DELAYED_SCRIPT_PATH}")
  rm "${DELAYED_SCRIPT_PATH}"

  echo "Executing delayed script on a healthy Tailscale:"
  for line in "${DELAYED_SCRIPT}"; do
    echo "[#] $line"
  done
  eval "${DELAYED_SCRIPT}"
fi
