#!/bin/sh
set -e

if [ -n "${TS_AUTHKEY}" ]; then
  if case "${TS_AUTHKEY}" in "tskey-auth-"*) true ;; *) false ;; esac; then
    echo "Found a valid tailscale auth key, using it to perform authentication"
  else
    echo "Given tailscale auth key is not valid: ${TS_AUTHKEY}"
    echo "Ignoring the key and trying to authenticate without it"
    export -n TS_AUTHKEY
  fi
fi

# Check that the device env variable is set
if [ -z "${WG_DEVICE+set}" ]; then
  echo "Environment variable \$WG_DEVICE is not set"
  exit 1
fi

# Check that the config file exists and has the right permissions
WG_CONF_PATH="/etc/wireguard/${WG_DEVICE}.conf"
if [ ! -f "${WG_CONF_PATH}" ]; then
  echo "Config file ${WG_CONF_PATH} does not exist"
  exit 1
fi
chmod 600 "${WG_CONF_PATH}"

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
export TS_TAILSCALED_EXTRA_ARGS="--port=${TS_PORT}"

/usr/local/bin/containerboot
