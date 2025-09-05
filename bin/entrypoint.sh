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

# Setup crontab to include reresolve-dns.sh script and run cron
echo -e "# Re-resolve WireGuard interface DNS\n*/10\t*\t*\t*\t*\t/tailguard/reresolve-dns.sh \"${WG_DEVICE}\"" >> /etc/crontabs/root
crond

echo "******************************"
echo "** Start Tailscale daemon   **"
echo "******************************"
export TS_AUTH_ONCE="true"
export TS_USERSPACE="false"
export TS_STATE_DIR="/tailguard/state"
export TS_KUBE_SECRET=""
export TS_TAILSCALED_EXTRA_ARGS="--tun="${TS_DEVICE}" --port=${TS_PORT}"

# Create firewall chains for enforcing tunneling between devices
iptables -N tg-forward
iptables -A tg-forward -s 100.64.0.0/10 ! -o "${WG_DEVICE}" -j DROP
ip6tables -N tg-forward
ip6tables -A tg-forward -s fd7a:115c:a1e0::/48 ! -o "${WG_DEVICE}" -j DROP

/usr/local/bin/containerboot
