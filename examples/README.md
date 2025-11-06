# TailGuard Examples

This directory contains some common use cases of TailGuard, each of them
connecting the Tailscale tailnet and WireGuard tunnels in slightly different
ways. Some of the scripts are not thoroughly tested, if you find any errors or
mistakes in them, please raise an issue or a PR.

**NOTE:** All scripts will create and overwrite the files `client.conf` and
`server.conf` in the current working directory, so please make sure not to run
them in a directory that contains files with those names or there may be data
loss.

## WireGuard as Exit Node

This is the original use case of TailGuard, connecting to a WireGuard server
that accepts and forwards the default route, and exposing it to the tailnet as
an exit node. In reality, you most likely don't want to use the generated
configuration files, but use a client file generated on the server.

Usage:
```
./wireguard-as-exit-node.sh server.example.com
```

## Simple Server

This is a WireGuard server in a container, which allows serving e.g. a HTTP
service to both the tailnet and to WireGuard clients alike, but does not forward
any connections between Tailscale nodes and WireGuard nodes. Think of it as a
node sitting between two networks, but not letting them see each other.

Usage:
```
./simple-server.sh server.example.com
```

## Simple Bridge

This is a WireGuard server, all clients connecting to it will get access to the
Tailscale tailnet. You might want to modify the DNS configuration parameter in
the client configuration to also include your tailnet domain, this allows
lookup of Tailscale nodes by hostname only. Connections to the Tailscale IP are
forwarded to the WireGuard client node

Usage:
```
./simple-bridge.sh server.example.com
```

## Tailscale Exit Node

This is a WireGuard server similar to the Simple Bridge example, with the
difference that it forwards all traffic to the optimal exit node, allowing to
use a Tailscale exit node through WireGuard. It also supports using the
`TS_DEST_IP` environment variable in case forwarding traffic the other way
around is also desired.

Usage:
```
./tailscale-exit-node.sh server.example.com
```

