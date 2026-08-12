FROM ubuntu:24.04 AS build

ARG DEBIAN_FRONTEND=noninteractive
ARG CHV_VERSION=v53.0
ARG CHV_EDK2_TAG=ch-1e1b96f126
ARG VIRTIOFSD_VERSION=v1.14.0
ARG CHV_SHA256=448af3d4e59b22c2987f7df94c213ad40fb53a10d437e42b5ee6c4fce7c29ecc
ARG CH_REMOTE_SHA256=13f32ba952e6791fd901f2279be2055fbacc64005f96c42a8e90d58860df84a7
ARG CLOUDHV_EFI_SHA256=460cefa75c72461745ac2f8e828ac8646475f93823101980dfc3f5967175c1ef
ARG CLOUDHV_SHA256=9fb511fc0dd423d90a79615a90a8ace9b9e078b4a115ea2c459e0ac2f4e60218
ARG VIRTIOFSD_COMMIT=c2540f8db14caba81c1e37fba23fc7bf2cd7f0dd
ENV LC_ALL=C.UTF-8

# ---------------------------------------------------------------------------
# Version pins — update these to bump the build.
# ---------------------------------------------------------------------------
ENV CHV_VERSION=${CHV_VERSION}
ENV CHV_EDK2_TAG=${CHV_EDK2_TAG}
ENV VIRTIOFSD_VERSION=${VIRTIOFSD_VERSION}
ENV CHV_SHA256=${CHV_SHA256}
ENV CH_REMOTE_SHA256=${CH_REMOTE_SHA256}
ENV CLOUDHV_EFI_SHA256=${CLOUDHV_EFI_SHA256}
ENV CLOUDHV_SHA256=${CLOUDHV_SHA256}
ENV VIRTIOFSD_COMMIT=${VIRTIOFSD_COMMIT}

# ---------------------------------------------------------------------------
# Minimal tools for downloading and building virtiofsd
# ---------------------------------------------------------------------------
RUN set -eux; \
    apt-get update; \
    apt-get install --yes --no-install-recommends \
        ca-certificates curl git \
        build-essential libcap-ng-dev libseccomp-dev patchelf pkg-config; \
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
    echo "${CHV_SHA256}  /opt/chv/bin/cloud-hypervisor" | sha256sum --check --strict; \
    echo "${CH_REMOTE_SHA256}  /opt/chv/bin/ch-remote" | sha256sum --check --strict; \
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
    echo "${CLOUDHV_EFI_SHA256}  /opt/chv/firmware/CLOUDHV_EFI.fd" | sha256sum --check --strict; \
    echo "${CLOUDHV_SHA256}  /opt/chv/firmware/CLOUDHV.fd" | sha256sum --check --strict; \
    ls -la /opt/chv/firmware/

# ---------------------------------------------------------------------------
# Build virtiofsd (Rust implementation)
# ---------------------------------------------------------------------------
WORKDIR /build/virtiofsd

RUN set -eux; \
    git clone --depth 1 --branch "${VIRTIOFSD_VERSION}" \
        https://gitlab.com/virtio-fs/virtiofsd.git .; \
    test "$(git rev-parse HEAD)" = "${VIRTIOFSD_COMMIT}"; \
    cargo build --release; \
    install -m 0755 target/release/virtiofsd /opt/chv/bin/virtiofsd; \
    strip /opt/chv/bin/virtiofsd; \
    /opt/chv/bin/virtiofsd --version

# Bundle virtiofsd's non-glibc libraries privately. DT_RPATH deliberately takes
# precedence over target-host copies so the validated bundle is used on every
# supported distribution without changing the global linker configuration.
RUN set -eux; \
    mkdir -p /opt/chv/lib /opt/chv/licenses; \
    ldd /opt/chv/bin/virtiofsd \
        | awk '/=> \/[^ ]+/ { print $3 }' \
        | while read -r library; do \
            case "$(basename "${library}")" in \
                libc.so.*) continue ;; \
            esac; \
            cp -L "${library}" "/opt/chv/lib/$(basename "${library}")"; \
        done; \
    patchelf --force-rpath --set-rpath '$ORIGIN/../lib' /opt/chv/bin/virtiofsd; \
    cp /usr/share/doc/libseccomp2/copyright /opt/chv/licenses/libseccomp2.copyright; \
    cp /usr/share/doc/libcap-ng0/copyright /opt/chv/licenses/libcap-ng0.copyright; \
    cp /usr/share/doc/libgcc-s1/copyright /opt/chv/licenses/libgcc-s1.copyright; \
    ldd /opt/chv/bin/virtiofsd | grep -F '/opt/chv/bin/../lib/libseccomp.so.2'; \
    ldd /opt/chv/bin/virtiofsd | grep -F '/opt/chv/bin/../lib/libcap-ng.so.0'; \
    ldd /opt/chv/bin/virtiofsd | grep -F '/opt/chv/bin/../lib/libgcc_s.so.1'; \
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
