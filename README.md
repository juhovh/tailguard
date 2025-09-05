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

Let's imagine you have a WireGuard server running on 192.168.68.1 that is able
to accept any IPv4 routes (i.e. `AllowedIPs = 0.0.0.0/0`), and its local LAN
network is 192.168.68.0/22. You should first download a WireGuard client config
and save it as `wg0.conf` under `config/`.

After you have the config downloaded, you need to generate a temporary auth key
for Tailscale. You can do this from https://login.tailscale.com/admin/machines
by selecting "Add device" -> "Linux server" -> "Generate install script". You
need to copy the `--auth-key=` argument value, this is your single use auth key.

Next you need to open docker-compose.yml and modify it as follows:

```
    environment:
      - WG_DEVICE=wg0
      - TS_PORT=41641
      - TS_HOSTNAME=tailguard
      - TS_DEST_IP=192.168.68.1
      - TS_ROUTES=192.168.68.0/22
      - TS_EXTRA_ARGS=--advertise-exit-node --accept-routes
      - TS_AUTHKEY=tskey-auth-xxxxxxxxxxxxxxxxxxxxxxx
```
This will use the device wg0 and therefore the wg0.conf file for WireGuard. It
will connect to the tailnet with hostname "tailguard", forward all connections
to itself to the router behind the tunnel, advertise the "192.168.68.0/22"
route to other tailnet hosts, advertise itself as an exit node, and
authenticate with the given authkey.

Now if you run `docker compose up` once, you can remove the `TS_AUTHKEY` and it
should keep working, as long as you keep your `state/` directory intact.

That's it, happy networking!

## License
 
The MIT License (MIT)

Copyright (c) 2025 Juho Vähä-Herttua

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
