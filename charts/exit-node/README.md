# TailGuard Exit Node Helm Chart

Kubernetes Helm Chart for a TailGuard exit node

## Usage

Clone the repository:

```bash
git clone https://github.com/juhovh/tailguard.git
```

Install the chart:

```bash
helm install exit-node-1 tailguard/charts/exit-node \
    --set "tailscale.preAuthKey=<tailscale preauth key>" \
    --set-file "tailguard.wirguardConfig=wg0.conf"

```

Alternatively if you use an alternative coordination/login server:
```bash
helm install exit-node-1 tailguard/charts/exit-node \
    --set "tailscale.loginServer=https://alt-login-server.example.com/" \
    --set "tailscale.preAuthKey=ts-key-xxxxxxxX" \
    --set-file "tailguard.wirguardConfig=wg0.conf"
```
