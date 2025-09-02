#!/bin/sh

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
(crontab -l; echo -e "# Re-resolve WireGuard interface DNS\n*/30\t*\t*\t*\t*\t/tailscale/reresolve-dns.sh \"${WG_DEVICE}\"") | crontab -

# Masquerade everything from tailscale subnet to wireguard
iptables -t nat -A POSTROUTING -o "${WG_DEVICE}" -s 100.64.0.0/10 -j MASQUERADE
ip6tables -t nat -A POSTROUTING -o "${WG_DEVICE}" -s fd7a:115c:a1e0::/48 -j MASQUERADE

echo "******************************"
echo "** Start Tailscale daemon   **"
echo "******************************"
export TS_AUTH_ONCE="true"
export TS_USERSPACE="false"
export TS_STATE_DIR="/tailscale/state"
export TS_KUBE_SECRET=""
/usr/local/bin/containerboot
