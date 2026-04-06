FROM ubuntu:24.04 AS build

ARG DEBIAN_FRONTEND=noninteractive
ENV LC_ALL=C.UTF-8

# ---------------------------------------------------------------------------
# Version pins — update these to bump the build.
# ---------------------------------------------------------------------------
ENV CHV_VERSION=v51.1
ENV CHV_EDK2_TAG=ch-13b4963ec4
ENV VIRTIOFSD_VERSION=v1.12.0

# ---------------------------------------------------------------------------
# Minimal tools for downloading and building virtiofsd
# ---------------------------------------------------------------------------
RUN set -eux; \
    apt-get update; \
    apt-get install --yes --no-install-recommends \
        ca-certificates curl git \
        build-essential libcap-ng-dev libseccomp-dev pkg-config; \
    rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Install Rust toolchain (needed for virtiofsd)
# ---------------------------------------------------------------------------
RUN set -eux; \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --default-toolchain stable --profile minimal; \
    . "$HOME/.cargo/env"; \
    cargo --version

ENV PATH="/root/.cargo/bin:${PATH}"

# ---------------------------------------------------------------------------
# Download Cloud Hypervisor static binaries
# ---------------------------------------------------------------------------
RUN set -eux; \
    mkdir -p /opt/chv/bin; \
    curl -fSL "https://github.com/cloud-hypervisor/cloud-hypervisor/releases/download/${CHV_VERSION}/cloud-hypervisor-static" \
        -o /opt/chv/bin/cloud-hypervisor; \
    curl -fSL "https://github.com/cloud-hypervisor/cloud-hypervisor/releases/download/${CHV_VERSION}/ch-remote-static" \
        -o /opt/chv/bin/ch-remote; \
    chmod 0755 /opt/chv/bin/cloud-hypervisor /opt/chv/bin/ch-remote; \
    /opt/chv/bin/cloud-hypervisor --version; \
    /opt/chv/bin/ch-remote --version

# ---------------------------------------------------------------------------
# Download Cloud Hypervisor firmware (custom EDK2 build)
# ---------------------------------------------------------------------------
RUN set -eux; \
    mkdir -p /opt/chv/firmware; \
    curl -fSL "https://github.com/cloud-hypervisor/edk2/releases/download/${CHV_EDK2_TAG}/CLOUDHV_EFI.fd" \
        -o /opt/chv/firmware/CLOUDHV_EFI.fd; \
    curl -fSL "https://github.com/cloud-hypervisor/edk2/releases/download/${CHV_EDK2_TAG}/CLOUDHV.fd" \
        -o /opt/chv/firmware/CLOUDHV.fd; \
    ls -la /opt/chv/firmware/

# ---------------------------------------------------------------------------
# Build virtiofsd (Rust implementation)
# ---------------------------------------------------------------------------
WORKDIR /build/virtiofsd

RUN set -eux; \
    git clone --depth 1 --branch "${VIRTIOFSD_VERSION}" \
        https://gitlab.com/virtio-fs/virtiofsd.git .; \
    cargo build --release; \
    install -m 0755 target/release/virtiofsd /opt/chv/bin/virtiofsd; \
    /opt/chv/bin/virtiofsd --version

# ---------------------------------------------------------------------------
# Create the self-extracting installer
# ---------------------------------------------------------------------------
COPY create-run-installer.sh install-chv.sh /build/scripts/
RUN chmod +x /build/scripts/*.sh && \
    /build/scripts/create-run-installer.sh

# ---------------------------------------------------------------------------
# Final stage — only the portable installer artifact
# ---------------------------------------------------------------------------
FROM scratch AS artifact

COPY --from=build /opt/chv/_packages/cloud-hypervisor-installer.run /cloud-hypervisor-installer.run

CMD ["/cloud-hypervisor-installer.run"]
