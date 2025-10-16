FROM golang:1.25.1-alpine AS build-env

ARG TS_VERSION="v1.88.4"

WORKDIR /go/src/tailscale

RUN \
  apk add --update --no-cache git && \
  git clone --branch "$TS_VERSION" https://github.com/tailscale/tailscale.git .

# Apply patches from branch in https://github.com/tailscale/tailscale/pull/14575
COPY ./tailscale-patches /tmp/tailscale-patches
RUN git -c user.name="TailGuard" -c user.email="" am /tmp/tailscale-patches/*.patch

RUN go mod download

ARG TARGETARCH
RUN \
  eval `CGO_ENABLED=0 GOOS=$(go env GOHOSTOS) GOARCH=$(go env GOHOSTARCH) go run ./cmd/mkversion` && \
  VERSION_LONG="$(echo $VERSION_LONG | rev | cut -d "-" -f 2- | rev) (TailGuard)" && \
  GOARCH=$TARGETARCH go install -ldflags="\
      -X 'tailscale.com/version.longStamp=$VERSION_LONG' \
      -X 'tailscale.com/version.shortStamp=$VERSION_SHORT' \
      -X 'tailscale.com/version.gitCommitStamp=$VERSION_GIT_HASH'" \
      -v ./cmd/tailscale ./cmd/tailscaled ./cmd/containerboot

FROM alpine:3.22.1

WORKDIR /tailguard

COPY --from=build-env /go/bin/* /usr/local/bin/
RUN \
  apk add --update --no-cache iptables ip6tables ipcalc curl wireguard-tools wireguard-go && \
  sed -i 's|^RESTARTCMD=$|RESTARTCMD="true"|' /usr/sbin/resolvconf && \
  sed -i 's|\[\[ $proto == -4 \]\] && cmd sysctl -q net\.ipv4\.conf\.all\.src_valid_mark=1|[[ $proto == -4 ]] \&\& [[ $(sysctl -n net.ipv4.conf.all.src_valid_mark) != 1 ]] \&\& cmd sysctl -q net.ipv4.conf.all.src_valid_mark=1|' /usr/bin/wg-quick

COPY bin/* ./
RUN chmod +x *.sh

HEALTHCHECK --interval=1m --timeout=10s --start-period=10s --start-interval=1s --retries=3 \
  CMD ["/tailguard/healthcheck.sh"]

ENTRYPOINT ["/tailguard/entrypoint.sh"]
