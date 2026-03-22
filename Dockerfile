# =============================================================================
# Quake 3 Arena Dedicated Server
# Multi-stage build: compile ioquake3 from source on Alpine
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1: Build ioquake3 dedicated server from source
# -----------------------------------------------------------------------------
FROM alpine:3.21 AS builder

# Pin to a specific audited commit for supply chain security
ARG IOQUAKE3_REPO=https://github.com/ioquake/ioq3.git
ARG IOQUAKE3_COMMIT=5956299e80b29ef3891bcec8e99cd3e680f34b1a

RUN apk add --no-cache \
    git \
    g++ \
    gcc \
    make \
    cmake \
    samurai \
    musl-dev \
    linux-headers \
    curl

WORKDIR /build

RUN git clone ${IOQUAKE3_REPO} ioq3 \
    && cd ioq3 \
    && git checkout ${IOQUAKE3_COMMIT}

WORKDIR /build/ioq3

# Build only the dedicated server (no client, no renderer)
RUN cmake -B build -G Ninja \
    -DCMAKE_INSTALL_PREFIX=/opt/quake3 \
    -DBUILD_CLIENT=OFF \
    -DBUILD_RENDERER_OPENGL1=OFF \
    -DBUILD_RENDERER_OPENGL2=OFF \
    -DBUILD_RENDERER_VULKAN=OFF \
    -DUSE_INTERNAL_LIBS=ON \
    && cmake --build build --parallel $(nproc) \
    && cmake --install build

# -----------------------------------------------------------------------------
# Stage 2: Minimal runtime image
# -----------------------------------------------------------------------------
FROM alpine:3.21

RUN apk add --no-cache \
    libstdc++ \
    libgcc \
    ca-certificates

# Create non-root user for the server process
RUN addgroup -S quake3 && adduser -S -G quake3 -h /opt/quake3 quake3

# Copy compiled server binary and game libraries from builder
COPY --from=builder /opt/quake3 /opt/quake3

# Copy entrypoint
COPY entrypoint.sh /opt/quake3/entrypoint.sh

RUN chmod +x /opt/quake3/entrypoint.sh \
    && chown -R quake3:quake3 /opt/quake3

# Standard Q3A server port (UDP)
EXPOSE 27960/udp

USER quake3
WORKDIR /opt/quake3

ENTRYPOINT ["/opt/quake3/entrypoint.sh"]
