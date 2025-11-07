# TailGuard

A simple Docker container app which allows connecting existing WireGuard hosts
to the Tailscale network, in case the device running WireGuard is locked in
and/or does not support Tailscale binaries.

The network topology will look roughly like this:
```
  +---------+                                                       +---------+
  | device1 |\                                                     /| device4 |
  +---------+ \                        VPS                        / +---------+
  +---------+  \ +-----------+    +-----------+    +-----------+ /  +---------+
  | device2 |----| Tailscale |<-->| TailGuard |<-->| WireGuard |----| device5 |
  +---------+  / +-----------+    +-----------+    +-----------+ \  +---------+
  +---------+ /                                                   \ +---------+
  | device3 |/                                                     \| device6 |
  +---------+                                                       +---------+
```

As usual, the tailnet is virtual and in reality connections are point-to-point,
but all connections to WireGuard are tunneled through the TailGuard server with
a fixed and persistent connection. As long as you have access to a server as
close to the WireGuard host as possible (ideally with a minimal ping), for
example a VPS, you can connect any WireGuard device to your tailnet.

## Benefits

Why would you want to do this? For most use cases it may be easier to connect
your device with Tailscale or WireGuard directly, but there are a couple of
benefits with this bridged approach:
- the WireGuard tunnel private key is stored only on a single machine, making
  the key management less work
- if you have a new device, you can simply log in to your tailnet with SSO,
  without having to transfer keys
- it's easier to switch between exit nodes in your tailnet, without having to
  reconnect to different VPNs
- you can have access to both your tailnet and WireGuard concurrently on your
  mobile device, which doesn't support multiple VPNs
- you can temporarily share access to your WireGuard tunnel with other people
  using Tailscale, without having to share any keys
- you can have a server that is connected to both tailnet and WireGuard hosts,
  and serving both sides equally
- you can create a WireGuard server that allows devices that don't support
  Tailscale to connect to the tailnet, including using tailnet exit nodes

## Installation

The simplest way to start TailGuard is to simply download a WireGuard config and
save it as `wg0.conf`. After that you can create an IPv6 network (optional, but
recommended) and start the container:

```
docker network create --ipv6 ip6net
docker run -it \
  -v ./wg0.conf:/etc/wireguard/wg0.conf -v ./state:/tailguard/state \
  --cap-add NET_ADMIN --device /dev/net/tun \
  --sysctl net.ipv4.ip_forward=1 --sysctl net.ipv6.conf.all.forwarding=1 \
  --sysctl net.ipv4.conf.all.src_valid_mark=1 \
  --network ip6net -p 41641:41641/udp \
  --name tailguard ghcr.io/juhovh/tailguard:latest
```

Docker will print you an URL where you need to log in to your tailnet, and after
that you should be good to go.

If you want to build the latest version of the image yourself, it might be best
to use `docker compose`. In that case you should store the `wg0.conf` file under
`config/`, build the latest image with `docker compose build` and finally run it
with `docker compose up`.

That's it, happy networking!

### Advanced settings

Let's imagine you have a WireGuard server running on 10.1.0.1 that is able to
accept any routes, and its local LAN network is 192.168.8.0/24. You have already
downloaded the WireGuard client config for this tunnel and saved it. Make sure
that the subnet 192.168.8.0/24 is explicitly mentioned in the AllowedIPs section
in addition to 0.0.0.0/0, for TailGuard to pick it up. It should look something
like this:

```
[Interface]
PrivateKey = <REDACTED>
Address = 10.1.0.2/24,fd00:ed7c:a960:6e9b::2/64
DNS = 10.1.0.1,fd00:ed7c:a960:6e9b::1
MTU = 1420

[Peer]
PublicKey = <REDACTED>
PresharedKey = <REDACTED>
AllowedIPs = 0.0.0.0/0,::/0,192.168.8.0/24
Endpoint = <REDACTED>:51820
PersistentKeepalive = 25
```

Next you can either add `-e TS_DEST_IP=10.1.0.1,fd00:ed7c:a960:6e9b::1` if
running directly, or open the docker-compose.yml and modify it as follows:

```
    environment:
      - TS_DEST_IP=10.1.0.1,fd00:ed7c:a960:6e9b::1
```

This will use the device wg0 and therefore the wg0.conf file for WireGuard. It
will connect to the tailnet, forward all connections targeting itself to the
router behind the tunnel, advertise the "192.168.8.0/24" route to other tailnet
hosts, advertise itself as an exit node, and authenticate with the given
authkey.

Supported configuration parameters through environment:
- `TG_EXPOSE_HOST` - Set to 1 if you want to allow connections from TS and WG peers
- `TG_CLIENT_MODE` - Set to 1 to behave as a Tailscale client, allows setting an exit node
- `TG_NAMESERVERS` - Fallback nameservers for resolving hostnames (**default:** Cloudflare 1.1.1.1)
- `WG_DEVICE` - WireGuard device name, must be valid and match config file name (**default:** wg0)
- `WG_ISOLATE_PEERS` - Set to 1 to isolate WireGuard peers from each other
- `TS_DEVICE` - Tailscale device name, must be a valid device name (**default:** tailscale0)
- `TS_PORT` - Tailscale port number, should be exposed by Docker (**default:** 41641)
- `TS_LOGIN_SERVER` - URL of the control server if not using Tailscale default
- `TS_AUTHKEY` - Tailscale auth key for authentication if used
- `TS_HOSTNAME` - Tailscale hostname for this device if used
- `TS_DEST_IP` - Destination IP to route Tailscale traffic to, IPv4 and/or IPv6
- `TS_ROUTES` - Set routes to advertise, overrides autodetected routes if needed
- `TS_EXIT_NODE` - Set Tailscale exit node, only works with client mode enabled
- `TS_WEBCLIENT` - Set to 1 if you want to enable the web interface on port 5252

Some of these parameteres follow the naming of Tailscale Docker image
[parameters](https://tailscale.com/kb/1282/docker), in which case they should
also work the same way.

### Two-way routing between the networks

Unlike Tailscale, WireGuard itself does not handle any routing. Therefore, the
WireGuard subnets and routes are automatically advertised on the Tailscale
network, but it doesn't work the other way around.

Let's say your TailGuard node has IP addresses `10.1.0.2` and
`fd00:ed7c:a960:6e9b::2` for the WireGuard tunnel, like in the above config. You
likely want to add at least routes `100.64.0.0/10` and `fd7a:115c:a1e0::/48`
(Tailscale private address spaces) to be routed through `10.1.0.2`.

The easiest way is to modify the AllowedIPs section to include the Tailscale
network segments and any other subnets you'd like to route through TailGuard:

```
[Peer]
PublicKey = <REDACTED>
PresharedKey = <REDACTED>
AllowedIPs = 10.1.0.2/32,fd00:ed7c:a960:6e9b::2/128,100.64.0.0/10,fd7a:115c:a1e0::/48
```

If your router doesn't allow modifying the WireGuard configuration, you could
use its routing UI or the console to do something along the lines of:

```
ip route add 100.64.0.0/10 via 10.1.0.2 dev wgserver
ip route add fd7a:115c:a1e0::/48 via fd00:ed7c:a960:6e9b::2 dev wgserver
```

If you have additional subnets in your tailnet (e.g. `192.168.1.0/24`) that
you'd like to access, just add similar routing rules for those. TailGuard should
take care of forwarding all the published subnets to the tailnet, as long as it
is able to receive packets through the WireGuard tunnel first.

For more examples, please see the [examples](examples) directory.
