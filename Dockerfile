FROM golang:1.25.5-alpine3.23 AS build-env

# Install latest version of git
RUN apk add --update --no-cache git

# Clone wireguard-tools for the reresolve-dns.sh script
ARG WG_TOOLS_VERSION="v1.0.20250521"
RUN git -c advice.detachedHead=false clone --branch "$WG_TOOLS_VERSION" \
  https://github.com/WireGuard/wireguard-tools.git /go/src/wireguard-tools

# Clone latest Tailscale version and patch it with customisation, some patches
# are lifted from the PR https://github.com/tailscale/tailscale/pull/14575
ARG TS_VERSION="v1.92.5"
WORKDIR /go/src/tailscale
COPY ./tailscale-patches /tmp/tailscale-patches
RUN \
  git -c advice.detachedHead=false clone --branch "$TS_VERSION" \
    https://github.com/tailscale/tailscale.git /go/src/tailscale && \
  git -c user.name="TailGuard" -c user.email="" am /tmp/tailscale-patches/*.patch

# Download dependencies and build Tailscale
RUN go mod download

ARG TARGETARCH
RUN \
  eval `CGO_ENABLED=0 GOOS=$(go env GOHOSTOS) GOARCH=$(go env GOHOSTARCH) go run ./cmd/mkversion` && \
  VERSION_LONG="$(echo $VERSION_LONG | rev | cut -d "-" -f 3- | rev)-TailGuard" && \
  GOARCH=$TARGETARCH go install -ldflags="\
      -X 'tailscale.com/version.longStamp=$VERSION_LONG' \
      -X 'tailscale.com/version.shortStamp=$VERSION_SHORT' \
      -X 'tailscale.com/version.gitCommitStamp=$VERSION_GIT_HASH'" \
      -v ./cmd/tailscale ./cmd/tailscaled ./cmd/containerboot

# Build tailguard daemon and install it
COPY ./tgdaemon /go/src/tgdaemon
WORKDIR /go/src/tgdaemon
RUN go mod download
RUN go install

FROM alpine:3.23.2

RUN \
  apk add --update --no-cache ethtool iptables ip6tables ipcalc curl wireguard-tools wireguard-go && \
  sed -i 's|^RESTARTCMD=$|RESTARTCMD="true"|' /usr/sbin/resolvconf && \
  sed -i 's|\[\[ $proto == -4 \]\] && cmd sysctl -q net\.ipv4\.conf\.all\.src_valid_mark=1|[[ $proto == -4 ]] \&\& [[ $(sysctl -n net.ipv4.conf.all.src_valid_mark) != 1 ]] \&\& cmd sysctl -q net.ipv4.conf.all.src_valid_mark=1|' /usr/bin/wg-quick

WORKDIR /tailguard

COPY --from=build-env /go/src/wireguard-tools/contrib/reresolve-dns/reresolve-dns.sh ./
COPY --from=build-env /go/bin/* /usr/local/bin/

COPY bin/* ./
RUN chmod 755 *.sh

HEALTHCHECK --interval=1m --timeout=10s --start-period=10s --start-interval=1s --retries=3 \
  CMD ["/tailguard/healthcheck.sh"]

ENTRYPOINT ["/tailguard/entrypoint.sh"]
