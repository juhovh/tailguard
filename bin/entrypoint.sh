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

# Create wireguard device and set it up
echo "******************************"
echo "** Start WireGuard device   **"
echo "******************************"
echo "Device name: ${WG_DEVICE}"
/usr/bin/wg-quick up "${WG_DEVICE}"

# Setup backup DNS, crontab to include reresolve-dns.sh script, run cron
ip route add $(ip route show default | sed -e 's/default/1.1.1.1/')
ip route add $(ip route show default | sed -e 's/default/1.0.0.1/')
(resolvconf -l "${WG_DEVICE}" 2>/dev/null; echo -e "nameserver 1.1.1.1\nnameserver 1.0.0.1") | resolvconf -a "${WG_DEVICE}"
echo -e "# Re-resolve WireGuard interface DNS\n*\t*\t*\t*\t*\t/tailguard/reresolve-dns.sh \"${WG_DEVICE}\"" >> /etc/crontabs/root
crond

echo "******************************"
echo "** Start Tailscale daemon   **"
echo "******************************"

# See https://tailscale.com/kb/1282/docker for supported parameters
export TS_ACCEPT_DNS="false"
export TS_AUTH_ONCE="true"
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

export TS_EXTRA_ARGS="$(/tailguard/tailscale-args.sh "${WG_DEVICE}")"
export TS_TAILSCALED_EXTRA_ARGS="--tun="${TS_DEVICE}" --port=${TS_PORT}"

# Create firewall chains for enforcing tunneling between devices
iptables -P FORWARD DROP
iptables -N tg-forward
iptables -A tg-forward -i "${TS_DEVICE}" ! -o "${WG_DEVICE}" -j DROP
iptables -A tg-forward -i "${WG_DEVICE}" ! -o "${TS_DEVICE}" -j DROP
ip6tables -P FORWARD DROP
ip6tables -N tg-forward
ip6tables -A tg-forward -i "${TS_DEVICE}" ! -o "${WG_DEVICE}" -j DROP
ip6tables -A tg-forward -i "${WG_DEVICE}" ! -o "${TS_DEVICE}" -j DROP

# Set up masquerading, to allow traffic from WireGuard to Tailscale
iptables -t nat -A POSTROUTING -o "${TS_DEVICE}" -j MASQUERADE
ip6tables -t nat -A POSTROUTING -o "${TS_DEVICE}" -j MASQUERADE

/usr/local/bin/containerboot
