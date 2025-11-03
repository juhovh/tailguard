#!/bin/sh

if [ "$#" -ne 1 ]; then
  echo "Please provide a public endpoint address or hostname for this node" >&2
  echo "Usage: $0 [endpoint]" >&2
  exit 1
fi
ADDRESS="$1"

echo
echo "Starting TailGuard in a simple server mode, allowing connections from both sides"
echo "- The created client.conf configuration can be used to connect to the server"
echo "- Listening on UDP port 41641 for Tailscale tunnel connections"
echo "- Listening on UDP port 51820 for WireGuard client connections"
echo

echo "Generating server.conf and client.conf for linking Tailscale and WireGuard..."
$(dirname "$0")/bin/gen-wg-conf \
  server.conf 51820 "10.0.0.1/24,fdd0:5808:4c3f::1/64" "10.0.0.2,fdd0:5808:4c3f::2" \
  client.conf $ADDRESS "10.0.0.2/24,fdd0:5808:4c3f::2/64" "10.0.0.1,fdd0:5808:4c3f::1"
echo "...generation completed successfully!"
echo

echo "Starting up TailGuard in a container, using server.conf configuration"
docker network inspect ip6net 2>&1 > /dev/null || docker network create ip6net
docker run --rm -it \
  -v ./server.conf:/etc/wireguard/wg0.conf -v ./state:/tailguard/state \
  --cap-add NET_ADMIN --device /dev/net/tun \
  --sysctl net.ipv4.conf.all.src_valid_mark=1 \
  --env TG_EXPOSE_HOST=1 --env TG_CLIENT_MODE=1 --env WG_ISOLATE_PEERS=1 --env TS_ROUTES= \
  --network ip6net -p 41641:41641/udp -p 51820:51820/udp \
  --name tailguard ghcr.io/juhovh/tailguard:latest
