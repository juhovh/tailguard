FROM golang:1.25.3-alpine AS build-env

# Install latest version of git
RUN apk add --update --no-cache git

# Clone wireguard-tools for the reresolve-dns.sh script
ARG WG_TOOLS_VERSION="v1.0.20250521"
RUN git clone --branch "$WG_TOOLS_VERSION" https://github.com/WireGuard/wireguard-tools.git /go/src/wireguard-tools

# Clone latest Tailscale version and patch it with customisation, some patches
# are lifted from the PR https://github.com/tailscale/tailscale/pull/14575
ARG TS_VERSION="v1.90.5"
WORKDIR /go/src/tailscale
COPY ./tailscale-patches /tmp/tailscale-patches
RUN \
  git clone --branch "$TS_VERSION" https://github.com/tailscale/tailscale.git /go/src/tailscale && \
  git -c user.name="TailGuard" -c user.email="" am /tmp/tailscale-patches/*.patch

# Download dependencies and build Tailscale
RUN go mod download

ARG TARGETARCH
RUN \
  eval `CGO_ENABLED=0 GOOS=$(go env GOHOSTOS) GOARCH=$(go env GOHOSTARCH) go run ./cmd/mkversion` && \
  VERSION_LONG="$(echo $VERSION_LONG | rev | cut -d "-" -f 3- | rev) (TailGuard)" && \
  GOARCH=$TARGETARCH go install -ldflags="\
      -X 'tailscale.com/version.longStamp=$VERSION_LONG' \
      -X 'tailscale.com/version.shortStamp=$VERSION_SHORT' \
      -X 'tailscale.com/version.gitCommitStamp=$VERSION_GIT_HASH'" \
      -v ./cmd/tailscale ./cmd/tailscaled ./cmd/containerboot

FROM alpine:3.22.2

WORKDIR /tailguard

COPY --from=build-env /go/bin/* /usr/local/bin/
COPY --from=build-env /go/src/wireguard-tools/contrib/reresolve-dns/reresolve-dns.sh ./

RUN \
  apk add --update --no-cache iptables ip6tables ipcalc curl wireguard-tools wireguard-go && \
  sed -i 's|^RESTARTCMD=$|RESTARTCMD="true"|' /usr/sbin/resolvconf && \
  sed -i 's|\[\[ $proto == -4 \]\] && cmd sysctl -q net\.ipv4\.conf\.all\.src_valid_mark=1|[[ $proto == -4 ]] \&\& [[ $(sysctl -n net.ipv4.conf.all.src_valid_mark) != 1 ]] \&\& cmd sysctl -q net.ipv4.conf.all.src_valid_mark=1|' /usr/bin/wg-quick

COPY bin/* ./
RUN chmod 755 *.sh

HEALTHCHECK --interval=1m --timeout=10s --start-period=10s --start-interval=1s --retries=3 \
  CMD ["/tailguard/healthcheck.sh"]

ENTRYPOINT ["/tailguard/entrypoint.sh"]
