#!/bin/sh
set -e

# This is a path to execute scripts on a healthy Tailscale,
# must be the same path as set in healtcheck.sh
DELAYED_SCRIPT_PATH="/tailguard/.delayed-script.sh"

# Use the top 8 bits for WireGuard forwarding mark, they
# are not used by neither Tailscale nor wg-quick scripts
WG_FORWARD_MARK="0x1000000/0xff000000"

if [ ${TG_EXPOSE_HOST:-0} -eq 1 ]; then
  echo "Expose host to Tailscale and WireGuard networks"
else
  # Default to not exposing the host
  export TG_EXPOSE_HOST=0
fi

if [ ${TG_CLIENT_MODE:-0} -eq 1 ]; then
  echo "Using Tailscale client mode, advertisements disabled, exit node allowed"
else
  # Default to not being in client mode
  export TG_CLIENT_MODE=0
fi

PORT_REGEX="^([1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$"
if [ -z "${TG_WEBUI_PORT+set}" ]; then
  # If not set, we simply disable WebUI
  echo "WebUI not enabled for this instance"
elif echo "${TG_WEBUI_PORT}" | grep -Eq "$PORT_REGEX"; then
  echo "WebUI enabled on port $TG_WEBUI_PORT"
  export TG_WEBUI_PORT
else
  echo "Invalid \$TG_WEBUI_PORT value: $TG_WEBUI_PORT"
  exit 1
fi

if [ -z "${TG_NAMESERVERS+set}" ]; then
  echo "Environment variable \$TS_NAMESERVERS is not set, using Cloudflare 1.1.1.1 servers"
  export TG_NAMESERVERS="1.1.1.1, 2606:4700:4700::1111, 1.0.0.1, 2606:4700:4700::1001"
fi

# Check that the WireGuard device env variable is set
if [ -z "${WG_DEVICE+set}" ]; then
  echo "Environment variable \$WG_DEVICE is not set, defaulting to wg0"
  export WG_DEVICE="wg0"
fi

if [ ${WG_ISOLATE_PEERS:-0} -eq 1 ]; then
  echo "Isolating WireGuard peers from each other"
else
  # Default to not isolating peers
  export WG_ISOLATE_PEERS=0
fi

# Check that the config file exists and has the right permissions
WG_CONF_PATH="/etc/wireguard/${WG_DEVICE}.conf"
if [ ! -f "${WG_CONF_PATH}" ]; then
  echo "Config file ${WG_CONF_PATH} does not exist, exiting"
  exit 1
fi
chmod 600 "${WG_CONF_PATH}"

# Check that the Tailscale device env variable is set
if [ -z "${TS_DEVICE+set}" ]; then
  echo "Environment variable \$TS_DEVICE is not set, defaulting to tailscale0"
  export TS_DEVICE="tailscale0"
fi

# Check that the Tailscale port env variable is set
if [ -z "${TS_PORT+set}" ]; then
  echo "Environment variable \$TS_PORT is not set, defaulting to 41641"
  export TS_PORT="41641"
fi

# Validate TS_DEST_IP to contain exactly one IPv4 and/or one IPv6 address
if [ -n "${TS_DEST_IP}" ]; then
  TS_DEST_IPV4=""; TS_DEST_IPV6=""
  for dest_ip in $(echo "${TS_DEST_IP}" | tr ',' '\n'); do
    if ! ipcalc -s -c "$dest_ip"; then
      echo "Found invalid \$TS_DEST_IP address: $dest_ip"
      exit 1
    elif ipcalc -s -c -4 "$dest_ip" && [ -z "${TS_DEST_IPV4}" ]; then TS_DEST_IPV4="$dest_ip"
    elif ipcalc -s -c -6 "$dest_ip" && [ -z "${TS_DEST_IPV6}" ]; then TS_DEST_IPV6="$dest_ip"
    else
      echo "Variable \$TS_DEST_IP contains multiple addresses of the same type: ${TS_DEST_IP}"
      exit 1
    fi
  done
fi

# https://tailscale.com/kb/1320/performance-best-practices#ethtool-configuration
NETDEV=$(ip -o -4 route show default | cut -f 5 -d " ")
[ -z "$NETDEV" ] && NETDEV=$(ip -o -6 route show default | cut -f 5 -d " ")
if [ -n "$NETDEV" ] && ethtool -k $NETDEV | grep -q rx-udp-gro-forwarding; then
  echo "Setting rx-udp-gro-forwarding on rx-gro-list off for device $NETDEV"
  ethtool -K $NETDEV rx-udp-gro-forwarding on rx-gro-list off
fi

# Create wireguard device and set it up
echo "******************************"
echo "** Start WireGuard device   **"
echo "******************************"
echo "Device name: ${WG_DEVICE}"
/usr/bin/wg-quick up "${WG_DEVICE}"

# Get required port and route information from WireGuard
WG_LISTEN_PORT=$(wg show "${WG_DEVICE}" listen-port)
WG_DEFAULT_ROUTES_FOUND=0
WG_SUBNETS_FOUND=""

for subnet in $(wg show "${WG_DEVICE}" allowed-ips | cut -f 2 | tr ' ' '\n'); do
  if [[ "$subnet" = "0.0.0.0/0" || "$subnet" = "::/0" ]]; then
    WG_DEFAULT_ROUTES_FOUND=1
    continue
  fi
  [ -n "${WG_SUBNETS_FOUND}" ] && WG_SUBNETS_FOUND="${WG_SUBNETS_FOUND},"
  WG_SUBNETS_FOUND="${WG_SUBNETS_FOUND}${subnet}"
done

# Set fwmark for the WireGuard device, unless already set by wg-quick
WG_FWMARK=$(wg show "${WG_DEVICE}" fwmark)
if [ "${WG_FWMARK}" = "off" ]; then
  # No fwmark set by wg-quick, use listen-port as fwmark
  WG_FWMARK="${WG_LISTEN_PORT}"
  wg set "${WG_DEVICE}" fwmark "${WG_FWMARK}"
fi
WG_FWMARK=$(printf "%d" "${WG_FWMARK}")

# Setup backup DNS servers by adding them through resolvconf
for nameserver in $(echo "${TG_NAMESERVERS}" | tr "," "\n"); do
  if ! ipcalc -s -c "$nameserver"; then
    echo "Found an invalid nameserver \"$nameserver\", skipping..."
    continue
  elif [ -n "$(ip -4 route show default)" ] && ipcalc -s -c -4 "$nameserver"; then
    echo "Adding a fallback IPv4 nameserver \"$nameserver\""
    ip route add $(ip -4 route show default | sed -e "s/default/$nameserver/")
  elif [ -n "$(ip -6 route show default)" ] && ipcalc -s -c -6 "$nameserver"; then
    echo "Adding a fallback IPv6 nameserver \"$nameserver\""
    ip route add $(ip -6 route show default | sed -e "s/default/$nameserver/")
  else
    # No default route for the given address family, skip adding the nameserver
    continue
  fi
  (resolvconf -l "${WG_DEVICE}" 2>/dev/null; echo "nameserver $nameserver") | resolvconf -a "${WG_DEVICE}"
done

# Include reresolve-dns script to run every minute in crontab, start crond in background
echo -e "# Re-resolve WireGuard interface DNS\n*\t*\t*\t*\t*\t/tailguard/reresolve-dns.sh \"${WG_DEVICE}\"" >> /etc/crontabs/root
crond

echo "******************************"
echo "** Setup TailGuard firewall **"
echo "******************************"

# Drop all incoming packets by default, unless localhost or required
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -p udp --dport "${WG_LISTEN_PORT}" -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -P INPUT DROP

# Create a chain for TailGuard input, dropping incoming connections
iptables -N tg-input
if [ -n "${TG_WEBUI_PORT}" ]; then
  iptables -A tg-input -i "${WG_DEVICE}" -p tcp --dport "${TG_WEBUI_PORT}" -j ACCEPT
  iptables -A tg-input -i "${TS_DEVICE}" -p tcp --dport "${TG_WEBUI_PORT}" -j ACCEPT
fi
if [ ${TG_EXPOSE_HOST} -eq 1 ]; then
  iptables -A tg-input -i "${WG_DEVICE}" -j ACCEPT
  iptables -A tg-input -i "${TS_DEVICE}" -j ACCEPT
else
  # This is only for TS_DEVICE, which Tailscale accepts by default
  iptables -A tg-input -i "${TS_DEVICE}" -m state --state ESTABLISHED,RELATED -j ACCEPT
  iptables -A tg-input -i "${TS_DEVICE}" -j DROP
fi

# Create a chain for TailGuard forward, drop external destinations
iptables -P FORWARD DROP
iptables -N tg-forward
if [ ${WG_ISOLATE_PEERS} -ne 1 ]; then
  iptables -A tg-forward -i "${WG_DEVICE}" -o "${WG_DEVICE}" -j ACCEPT
fi
iptables -A tg-forward -i "${WG_DEVICE}" ! -o "${TS_DEVICE}" -j DROP
iptables -A tg-forward -i "${TS_DEVICE}" ! -o "${WG_DEVICE}" -j DROP
iptables -A tg-forward -i "${WG_DEVICE}" -j MARK --set-xmark "${WG_FORWARD_MARK}"

# Create a chain for TailGuard postrouting, masquerade packets. The
# Tailscale rules already set masquerade for Tailscale originating
# packets, so only WireGuard originating packets need the rule.
iptables -t nat -N tg-postrouting
iptables -t nat -A tg-postrouting -m mark --mark "${WG_FORWARD_MARK}" -j MASQUERADE

# Drop all incoming packets by default, unless localhost or required
ip6tables -A INPUT -i lo -j ACCEPT
ip6tables -A INPUT -p ipv6-icmp -j ACCEPT
ip6tables -A INPUT -p udp --dport "${WG_LISTEN_PORT}" -j ACCEPT
ip6tables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
ip6tables -P INPUT DROP

# Create a chain for TailGuard input, dropping incoming connections
ip6tables -N tg-input
if [ -n "${TG_WEBUI_PORT}" ]; then
  ip6tables -A tg-input -i "${WG_DEVICE}" -p tcp --dport "${TG_WEBUI_PORT}" -j ACCEPT
  ip6tables -A tg-input -i "${TS_DEVICE}" -p tcp --dport "${TG_WEBUI_PORT}" -j ACCEPT
fi
if [ ${TG_EXPOSE_HOST} -eq 1 ]; then
  ip6tables -A tg-input -i "${WG_DEVICE}" -j ACCEPT
  ip6tables -A tg-input -i "${TS_DEVICE}" -j ACCEPT
else
  # This is only for TS_DEVICE, which Tailscale accepts by default
  ip6tables -A tg-input -i "${TS_DEVICE}" -m state --state ESTABLISHED,RELATED -j ACCEPT
  ip6tables -A tg-input -i "${TS_DEVICE}" -j DROP
fi

# Create a chain for TailGuard forward, drop external destinations
ip6tables -P FORWARD DROP
ip6tables -N tg-forward
if [ ${WG_ISOLATE_PEERS} -ne 1 ]; then
  ip6tables -A tg-forward -i "${WG_DEVICE}" -o "${WG_DEVICE}" -j ACCEPT
fi
ip6tables -A tg-forward -i "${WG_DEVICE}" ! -o "${TS_DEVICE}" -j DROP
ip6tables -A tg-forward -i "${TS_DEVICE}" ! -o "${WG_DEVICE}" -j DROP
ip6tables -A tg-forward -i "${WG_DEVICE}" -j MARK --set-xmark "${WG_FORWARD_MARK}"

# Create a chain for TailGuard postrouting, masquerade packets
ip6tables -t nat -N tg-postrouting
ip6tables -t nat -A tg-postrouting -m mark --mark "${WG_FORWARD_MARK}" -j MASQUERADE

# Set PMTU discovery for both tun devices to avoid packet fragmentation
iptables -t mangle -A FORWARD -o "${WG_DEVICE}" -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
iptables -t mangle -A FORWARD -o "${TS_DEVICE}" -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
ip6tables -t mangle -A FORWARD -o "${WG_DEVICE}" -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
ip6tables -t mangle -A FORWARD -o "${TS_DEVICE}" -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

# Save WireGuard device fwmark in postrouting and restore it in prerouting
iptables -t mangle -A POSTROUTING -p udp -m mark --mark ${WG_FWMARK} -j CONNMARK --save-mark
iptables -t mangle -A PREROUTING -p udp -j CONNMARK --restore-mark
ip6tables -t mangle -A POSTROUTING -p udp -m mark --mark ${WG_FWMARK} -j CONNMARK --save-mark
ip6tables -t mangle -A PREROUTING -p udp -j CONNMARK --restore-mark

# Add Tailscale routing table to the routing rules, since it's not
# added by our patched Tailscale. This is required to prevent our
# WireGuard packets getting routed through the exit node. The values
# 5270 and 52 are hardcoded in the Tailscale source code.

echo "Setting Tailscale routing rules for mark ${WG_FWMARK}"
ip -4 rule add not from all fwmark ${WG_FWMARK} lookup 52 pref 5270
ip -6 rule add not from all fwmark ${WG_FWMARK} lookup 52 pref 5270

echo "All rules set up, waiting for healthcheck for finalisation"

echo "******************************"
echo "** Start TailGuard daemon   **"
echo "******************************"

if [ -n "${TG_WEBUI_PORT}" ]; then
  echo "Starting daemon, listening on port ${TG_WEBUI_PORT}"
  /usr/local/bin/tgdaemon --port ${TG_WEBUI_PORT} &
else
  echo "WebUI not enabled, daemon not started"
fi

echo "******************************"
echo "** Start Tailscale daemon   **"
echo "******************************"

# See https://tailscale.com/kb/1282/docker for supported parameters
if [ ${TG_CLIENT_MODE} -eq 1 ]; then
  # If in client mode, enable DNS but do not allow advertising any routes
  export TS_ACCEPT_DNS="true"
  ADVERTISE_EXIT_NODE=0
  # allow TS_EXIT_NODE
else
  # If not in client mode, allow advertising but do not allow exit nodes
  export TS_ACCEPT_DNS="false"
  ADVERTISE_EXIT_NODE=${WG_DEFAULT_ROUTES_FOUND:-0}
  unset TS_EXIT_NODE

  # If TS_ROUTES is not set, use routes from WireGuard configuration
  if [ -z "${TS_ROUTES+set}" ]; then
    export TS_ROUTES="${WG_SUBNETS_FOUND}"
  fi
fi
export TS_AUTH_ONCE="false"
# skip TS_AUTHKEY, allow passthrough
export -n TS_DEST_IP # handled in healthcheck.sh
export -n TS_HEALTHCHECK_ADDR_PORT
export TS_LOCAL_ADDR_PORT="127.0.0.1:9002"
export TS_ENABLE_HEALTH_CHECK="true"
export TS_ENABLE_METRICS="false"
# skip TS_HOSTNAME, allow passthrough
export TS_KUBE_SECRET=""
export -n TS_OUTBOUND_HTTP_PROXY_LISTEN
# skip TS_ROUTES, handled earlier
export -n TS_SERVE_CONFIG
export -n TS_SOCKET
export -n TS_SOCKS5_SERVER
export TS_STATE_DIR="/tailguard/state"
export TS_USERSPACE="false"

export TS_NETMON_IGNORE="${WG_DEVICE}"
export TS_TAILSCALED_EXTRA_ARGS="--tun="${TS_DEVICE}" --port=${TS_PORT}"
TS_EXTRA_ARGS="--reset --accept-routes"
if [ -n "${TS_LOGIN_SERVER}" ]; then TS_EXTRA_ARGS="$TS_EXTRA_ARGS --login-server=${TS_LOGIN_SERVER}"; fi
if [ -n "${TS_EXIT_NODE}" ]; then TS_EXTRA_ARGS="$TS_EXTRA_ARGS --exit-node=${TS_EXIT_NODE} --exit-node-allow-lan-access"; fi
if [ ${ADVERTISE_EXIT_NODE} -eq 1 ]; then TS_EXTRA_ARGS="$TS_EXTRA_ARGS --advertise-exit-node"; fi
export TS_EXTRA_ARGS

# Set the exit node information second time in healthcheck.sh once the system is healthy,
# since autoselection in Tailscale doesn't work for some reason when set on startup,
# see https://github.com/tailscale/tailscale/issues/17768 for more details
if [ -n "${TS_EXIT_NODE}" ]; then
  echo "Adding re-setting of the exit node to a delayed script to support autoselect"
  echo "tailscale set --exit-node=${TS_EXIT_NODE} --exit-node-allow-lan-access" >> "${DELAYED_SCRIPT_PATH}"
fi

echo "Starting tailscaled with args: ${TS_TAILSCALED_EXTRA_ARGS}"
echo "Starting tailscale with args: ${TS_EXTRA_ARGS}"

/usr/local/bin/containerboot
