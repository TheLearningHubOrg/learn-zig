# Multi-stage Dockerfile for Zig 0.13 application
FROM alpine:3.20 AS builder

RUN apk add --no-cache curl tar xz && \
    ARCH=$(uname -m) && \
    case "$ARCH" in \
        x86_64) ZIG_ARCH="x86_64" ;; \
        aarch64) ZIG_ARCH="aarch64" ;; \
        *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
    esac && \
    curl -fsSL "https://ziglang.org/download/0.13.0/zig-linux-${ZIG_ARCH}-0.13.0.tar.xz" -o zig.tar.xz && \
    tar -xf zig.tar.xz && \
    mv "zig-linux-${ZIG_ARCH}-0.13.0" /opt/zig && \
    ln -s /opt/zig/zig /usr/local/bin/zig && \
    rm zig.tar.xz

WORKDIR /app
COPY . .

RUN zig build test && zig build -Doptimize=ReleaseSafe

FROM alpine:3.20 AS runner
WORKDIR /app
COPY --from=builder /app/zig-out/bin/learn-zig /app/learn-zig

ENTRYPOINT ["/app/learn-zig"]
