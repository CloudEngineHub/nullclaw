FROM ubuntu:24.04

ARG ZIG_VERSION=0.16.0

RUN apt-get update && apt-get install -y bash ca-certificates curl python3 xz-utils && rm -rf /var/lib/apt/lists/*

COPY .github/scripts/install-zig.sh /tmp/install-zig.sh
RUN chmod +x /tmp/install-zig.sh && \
    GITHUB_PATH=/tmp/zig-path bash /tmp/install-zig.sh "${ZIG_VERSION}" && \
    install_dir="$(cat /tmp/zig-path)" && \
    ln -s "${install_dir}/zig" /usr/local/bin/zig

WORKDIR /opt/websocket
COPY . .

ENTRYPOINT ["bash", "-lc", "zig build test -Dforce_blocking=false && zig build test -Dforce_blocking=true"]
