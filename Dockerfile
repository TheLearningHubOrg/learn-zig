# Zig HTTP service: build a static ReleaseSafe binary, ship it on distroless.

# ---- build ---------------------------------------------------------------------
FROM alpine:3.22 AS build
ARG ZIG_VERSION=0.17.0
# BuildKit sets TARGETARCH (amd64 or arm64) for the platform being built.
ARG TARGETARCH
# Checksums come from https://ziglang.org/download/index.json.
RUN set -eu; \
    apk add --no-cache curl xz; \
    case "${TARGETARCH:-amd64}" in \
      amd64) ZIG_ARCH=x86_64;  ZIG_SHA=1cbe9df9f27e6b78d14ccbca43b6703a404ef79ef1c463de901d7f088d4e2026 ;; \
      arm64) ZIG_ARCH=aarch64; ZIG_SHA=9e8d11661d4ae3bd57702a3832781e23ad151dde5798e16a5ccd503f65234ff8 ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://ziglang.org/download/${ZIG_VERSION}/zig-${ZIG_ARCH}-linux-${ZIG_VERSION}.tar.xz" -o /tmp/zig.tar.xz; \
    echo "${ZIG_SHA}  /tmp/zig.tar.xz" | sha256sum -c -; \
    mkdir -p /opt/zig; \
    tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1; \
    rm /tmp/zig.tar.xz
ENV PATH="/opt/zig:${PATH}"

WORKDIR /src
# Manifests first: this layer only changes when dependencies change.
COPY build.zig build.zig.zon ./
RUN zig build --fetch
COPY src ./src
COPY examples ./examples
# Without libc, Zig links Linux executables statically.
RUN zig build -Doptimize=safe --prefix /out

# ---- runtime -------------------------------------------------------------------
FROM gcr.io/distroless/static-debian12:nonroot AS runtime
COPY --from=build /out/bin/learn-zig /usr/local/bin/learn-zig
ENV PORT=8080
EXPOSE 8080
USER nonroot
ENTRYPOINT ["/usr/local/bin/learn-zig"]
