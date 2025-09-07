# TailGuard

A simple Docker container app which allows connecting existing WireGuard
servers to the Tailscale network, in case the device running WireGuard is
locked in and/or does not support Tailscale binaries.

The network topology will look roughly like this:
```
  +---------+
  | device1 |\
  +---------+ \                      VPS
  +---------+  \ +---------+    +-----------+      +-----------+
  | device2 |----| tailnet |----| TailGuard |<---->| WireGuard |
  +---------+  / +---------+    +-----------+      +-----------+
  +---------+ /
  | device3 |/
  +---------+
```

As usual, the tailnet is virtual and in reality connections are point-to-point,
but all connections to WireGuard are tunneled through the TailGuard server with
a fixed and persistent connection. As long as you have access to a server as
close to the WireGuard server as possible (ideally with a minimal ping), for
example a VPS, you can connect any WireGuard device to your tailnet.

## Benefits

Why would you want to do this? For most use cases it may be easier to connect
your device with WireGuard directly, but there are a couple of benefits with
this bridged approach:
- the WireGuard tunnel private key is stored only on a single machine, making
  the key management less work
- if you have a new device, you can simply log in to your tailnet with SSO,
  without having to transfer keys
- it's easier to switch between exit nodes in your tailnet, without having to
  reconnect to different VPNs
- you can have access to both your tailnet and WireGuard concurrently on your
  mobile device, which doesn't support multiple VPNs

## Installation

The simplest way to start TailGuard is to simply download a WireGuard client
config and save it as `wg0.conf` under `config/`. After that you can run `docker
compose up` and login to Tailscale through the URL shown in the logs.

That's it, happy networking!

### Advanced settings

Let's imagine you have a WireGuard server running on 192.168.68.1 that is able
to accept any IPv4 routes (i.e. `AllowedIPs = 0.0.0.0/0`), and its local LAN
network is 192.168.68.0/22. You have already downloaded the WireGuard client
config for this tunnel and saved it as `wg0.conf` under `config/`. Make sure
that the subnet 192.168.68.0/22 is explicitly mentioned in the AllowedIPs
section in addition to 0.0.0.0/0, for TailGuard to pick it up.

Next you can open docker-compose.yml and modify it as follows:

```
    environment:
      - TS_DEST_IP=192.168.68.1
```

This will use the device wg0 and therefore the wg0.conf file for WireGuard. It
will connect to the tailnet with hostname "tailguard", forward all connections
targeting itself to the router behind the tunnel, advertise the
"192.168.68.0/22" route to other tailnet hosts, advertise itself as an exit
node, and authenticate with the given authkey.

Supported configuration parameters through environment:
- `WG_DEVICE` - WireGuard device name, must be valid and match config file name
- `TS_DEVICE` - Tailscale device name, must be valid and defaults to tailscale0
- `TS_PORT` - Tailscale port number, should be exposed and defaults to 41641
- `TS_AUTHKEY` - Tailscale auth key for authentication if used
- `TS_DEST_IP` - Destination IP to route Tailscale traffic to
- `TS_HOSTNAME` - Tailscale hostname for this device if defined

### Two-way routing between the networks

Unlike Tailscale, WireGuard itself does not handle any routing. Therefore, the
WireGuard subnets and routes are automatically advertised on the Tailscale
network, but it doesn't work the other way around.

Let's say your TailGuard node has an IP addresses `10.1.0.2` and
`fd00:ed7c:a960:6e9b::2` for the WireGuard tunnel. You likely want to add at
least routes `100.64.0.0/10` and `fd7a:115c:a1e0::/48` (Tailscale private
address spaces) to be routed through `10.5.5.2`. You can do this through
something along the lines of:

```
ip route add 100.64.0.0/10 via 10.1.0.2 dev wgserver
ip route add fd7a:115c:a1e0::/48 via fd00:ed7c:a960:6e9b::2 dev wgserver
```

If you have additional subnets in your tailnet (e.g. `192.168.1.0/24`) that
you'd like to access, just add similar routing rules for those. TailGuard should
take care of all the forwarding all published subnets to the tailnet, as long as
it is able to receive packets through the WireGuard tunnel first.

## License
 
The MIT License (MIT)

Copyright (c) 2025 Juho Vähä-Herttua

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
