FROM tailscale/tailscale:v1.86.5

WORKDIR /tailguard

RUN \
  apk fix --update --no-cache iptables ip6tables && \
  apk add --update --no-cache wireguard-tools && \
  sed -i 's|\[\[ $proto == -4 \]\] && cmd sysctl -q net\.ipv4\.conf\.all\.src_valid_mark=1|[[ $proto == -4 ]] \&\& [[ $(sysctl -n net.ipv4.conf.all.src_valid_mark) != 1 ]] \&\& cmd sysctl -q net.ipv4.conf.all.src_valid_mark=1|' /usr/bin/wg-quick

COPY bin/* ./
RUN chmod +x *.sh

HEALTHCHECK --interval=5m --timeout=3s --start-period=10s --start-interval=1s --retries=3 \
  CMD ["./healthcheck.sh"]

ENTRYPOINT ["./entrypoint.sh"]
