#!/bin/sh

if [ "$#" -ne 1 ]; then
  echo "Please provide a public address or hostname for the WireGuard server" >&2
  echo "Usage: $0 [endpoint]" >&2
  exit 1
fi
ADDRESS="$1"

echo
echo "Starting TailGuard in an exit node mode, routing all traffic through WireGuard"
echo "- The created server.conf configuration can be used in a WireGuard server"
echo "- Listening on UDP port 41641 for Tailscale tunnel connections"
echo

echo "Generating server.conf and client.conf for linking Tailscale and WireGuard..."
$(dirname "$0")/bin/gen-wg-conf \
  server.conf 51820 "10.0.0.1/24,fdd0:5808:4c3f::1/64" "10.0.0.2,fdd0:5808:4c3f::2" \
  client.conf $ADDRESS "10.0.0.2/24,fdd0:5808:4c3f::2/64" "0.0.0.0/0,::/0"
echo "...generation completed successfully!"
echo

echo "Starting up TailGuard in a container, using client.conf configuration"
docker network inspect ip6net 2>&1 > /dev/null || docker network create ip6net
docker run --rm -it \
  -v ./client.conf:/etc/wireguard/wg0.conf -v ./state:/tailguard/state \
  --cap-add NET_ADMIN --device /dev/net/tun \
  --sysctl net.ipv4.ip_forward=1 --sysctl net.ipv6.conf.all.forwarding=1 \
  --sysctl net.ipv4.conf.all.src_valid_mark=1 \
  --env TS_DEST_IP=10.0.0.2,fdd0:5808:4c3f::2 \
  --network ip6net -p 41641:41641/udp \
  --name tailguard ghcr.io/juhovh/tailguard:latest
