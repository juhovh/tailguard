#!/bin/sh
set -e

# Check that the WireGuard device env variable is set
if [ -z "${WG_DEVICE+set}" ]; then
  echo "Environment variable \$WG_DEVICE is not set, defaulting to wg0"
  export WG_DEVICE="wg0"
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

if [ -n "${TS_AUTHKEY}" ]; then
  if case "${TS_AUTHKEY}" in "tskey-auth-"*) true ;; *) false ;; esac; then
    echo "Found a valid tailscale auth key, using it to perform authentication"
  else
    echo "Given tailscale auth key is not valid: ${TS_AUTHKEY}"
    echo "Ignoring the key and trying to authenticate without it"
    export -n TS_AUTHKEY
  fi
fi

if [ ${TG_EXPOSE_HOST:-0} -eq 1 ]; then
  echo "Expose host to Tailscale and WireGuard networks"
else
  # Default to not exposing the host
  TG_EXPOSE_HOST=0
fi

if [ -z "${TG_NAMESERVERS+set}" ]; then
  echo "Environment variable \$TS_NAMESERVERS is not set, using Cloudflare 1.1.1.1 servers"
  TG_NAMESERVERS="1.1.1.1, 2606:4700:4700::1111, 1.0.0.1, 2606:4700:4700::1001"
fi

# Create wireguard device and set it up
echo "******************************"
echo "** Start WireGuard device   **"
echo "******************************"
echo "Device name: ${WG_DEVICE}"
/usr/bin/wg-quick up "${WG_DEVICE}"

# Setup backup DNS, crontab to include reresolve-dns.sh script, run cron
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
echo -e "# Re-resolve WireGuard interface DNS\n*\t*\t*\t*\t*\t/tailguard/reresolve-dns.sh \"${WG_DEVICE}\"" >> /etc/crontabs/root
crond

# Parse WG_PORTS_FOUND, WG_DEFAULT_ROUTES_FOUND, and WG_SUBNETS_FOUND variables
eval $(/tailguard/parse-wgconf.sh "${WG_DEVICE}")

echo "******************************"
echo "** Setup TailGuard firewall **"
echo "******************************"

# Drop all incoming packets by default, unless localhost or required
iptables -A INPUT -i lo -j ACCEPT
if [ -n "${WG_PORTS_FOUND}" ]; then
  echo "Allow incoming WireGuard connections on IPv4 ports: ${WG_PORTS_FOUND}"
  iptables -A INPUT -p udp --match multiport --dport "${WG_PORTS_FOUND}" -j ACCEPT
fi
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -P INPUT DROP

# Create a chain for TailGuard input, dropping incoming connections
# This is only for TS_DEVICE, which Tailscale accepts by default
iptables -N tg-input
if [ ${TG_EXPOSE_HOST} -eq 1 ]; then
  iptables -A tg-input -i "${TS_DEVICE}" -j ACCEPT
  iptables -A tg-input -i "${WG_DEVICE}" -j ACCEPT
else
  iptables -A tg-input -i "${TS_DEVICE}" -m state --state ESTABLISHED,RELATED -j ACCEPT
  iptables -A tg-input -i "${TS_DEVICE}" -j DROP
fi

# Create a chain for TailGuard forward, drop external destinations
iptables -P FORWARD DROP
iptables -N tg-forward
iptables -A tg-forward -i "${WG_DEVICE}" -o "${WG_DEVICE}" -j ACCEPT
iptables -A tg-forward -i "${TS_DEVICE}" ! -o "${WG_DEVICE}" -j DROP
iptables -A tg-forward -i "${WG_DEVICE}" ! -o "${TS_DEVICE}" -j DROP

# Create a chain for TailGuard postrouting, masquerade packets
iptables -t nat -N tg-postrouting
iptables -t nat -A tg-postrouting -o "${TS_DEVICE}" -j MASQUERADE

# Drop all incoming packets by default, unless localhost or required
ip6tables -A INPUT -i lo -j ACCEPT
ip6tables -A INPUT -p ipv6-icmp -j ACCEPT
if [ -n "${WG_PORTS_FOUND}" ]; then
  echo "Allow incoming WireGuard connections on IPv6 ports: ${WG_PORTS_FOUND}"
  ip6tables -A INPUT -p udp --match multiport --dport "${WG_PORTS_FOUND}" -j ACCEPT
fi
ip6tables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
ip6tables -P INPUT DROP

# Create a chain for TailGuard input, dropping incoming connections
# This is only for TS_DEVICE, which Tailscale accepts by default
ip6tables -N tg-input
if [ ${TG_EXPOSE_HOST} -eq 1 ]; then
  ip6tables -A tg-input -i "${TS_DEVICE}" -j ACCEPT
  ip6tables -A tg-input -i "${WG_DEVICE}" -j ACCEPT
else
  ip6tables -A tg-input -i "${TS_DEVICE}" -m state --state ESTABLISHED,RELATED -j ACCEPT
  ip6tables -A tg-input -i "${TS_DEVICE}" -j DROP
fi

# Create a chain for TailGuard forward, drop external destinations
ip6tables -P FORWARD DROP
ip6tables -N tg-forward
ip6tables -A tg-forward -i "${WG_DEVICE}" -o "${WG_DEVICE}" -j ACCEPT
ip6tables -A tg-forward -i "${TS_DEVICE}" ! -o "${WG_DEVICE}" -j DROP
ip6tables -A tg-forward -i "${WG_DEVICE}" ! -o "${TS_DEVICE}" -j DROP

# Create a chain for TailGuard postrouting, masquerade packets
ip6tables -t nat -N tg-postrouting
ip6tables -t nat -A tg-postrouting -o "${TS_DEVICE}" -j MASQUERADE

echo "All rules set up, waiting for healthcheck for finalisation"

echo "******************************"
echo "** Start Tailscale daemon   **"
echo "******************************"

# Set advertised routes to either user specified or autodetected ones
if [ -z "${TS_ROUTES+set}" ]; then
  ADVERTISE_ROUTES="${WG_SUBNETS_FOUND}"
else
  ADVERTISE_ROUTES="${TS_ROUTES}"
fi

# See https://tailscale.com/kb/1282/docker for supported parameters
export TS_ACCEPT_DNS="false"
export TS_AUTH_ONCE="false"
# skip TS_AUTHKEY, handled earlier
# skip TS_DEST_IP, allow passthrough
export -n TS_HEALTHCHECK_ADDR_PORT
export TS_LOCAL_ADDR_PORT="127.0.0.1:9002"
export TS_ENABLE_HEALTH_CHECK="true"
export TS_ENABLE_METRICS="false"
# skip TS_HOSTNAME, allow passthrough
export TS_KUBE_SECRET=""
export -n TS_OUTBOUND_HTTP_PROXY_LISTEN
export -n TS_ROUTES
export -n TS_SERVE_CONFIG
export -n TS_SOCKET
export -n TS_SOCKS5_SERVER
export TS_STATE_DIR="/tailguard/state"
export TS_USERSPACE="false"

export TS_NETMON_IGNORE="${WG_DEVICE}"
export TS_TAILSCALED_EXTRA_ARGS="--tun="${TS_DEVICE}" --port=${TS_PORT}"
TS_EXTRA_ARGS="--reset --accept-dns=false --accept-routes"
if [ -n "${TS_LOGIN_SERVER}" ]; then TS_EXTRA_ARGS="$TS_EXTRA_ARGS --login-server=${TS_LOGIN_SERVER}"; fi
if [ ${WG_DEFAULT_ROUTES_FOUND:-0} -eq 1 ]; then TS_EXTRA_ARGS="$TS_EXTRA_ARGS --advertise-exit-node"; fi
if [ -n "${ADVERTISE_ROUTES}" ]; then TS_EXTRA_ARGS="$TS_EXTRA_ARGS --advertise-routes=${ADVERTISE_ROUTES}"; fi
export TS_EXTRA_ARGS

echo "Starting tailscaled with args: ${TS_TAILSCALED_EXTRA_ARGS}"
echo "Starting tailscale with args: ${TS_EXTRA_ARGS}"

/usr/local/bin/containerboot
