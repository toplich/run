FROM debian:bookworm-slim

ENV WG_I_PREFER_BUGGY_USERSPACE_TO_POLISHED_KMOD=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    wireguard-tools \
    iproute2 \
    iputils-ping \
    ca-certificates \
    bash && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY wireguard-go /usr/bin/wireguard-go
COPY wg0.conf /etc/wireguard/wg0.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /usr/bin/wireguard-go /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["tail", "-f", "/dev/null"]
