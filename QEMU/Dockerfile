FROM ubuntu:24.04 AS build

ARG DEBIAN_FRONTEND=noninteractive
ARG QEMU_VERSION=11.1.0
ARG QEMU_SHA256=6ee1d1a61f68212476b27108c26da5f449dc09b626d42f8279ba0dc2e08fa858
ARG LIBTPMS_VERSION=v0.10.2
ARG LIBTPMS_COMMIT=03ff2481e133540be3b3ffe3daa1483d2a73d967
ARG SWTPM_VERSION=v0.10.1
ARG SWTPM_COMMIT=53841482b0a9a1dfe63a120b00283acfe588ee72
ARG VIRTIOFSD_VERSION=v1.14.0
ARG VIRTIOFSD_COMMIT=c2540f8db14caba81c1e37fba23fc7bf2cd7f0dd
ENV LC_ALL=C.UTF-8

# ---------------------------------------------------------------------------
# Version pins — update these to bump the build.
# ---------------------------------------------------------------------------
ENV QEMU_VERSION=${QEMU_VERSION}
ENV QEMU_SHA256=${QEMU_SHA256}
ENV LIBTPMS_VERSION=${LIBTPMS_VERSION}
ENV LIBTPMS_COMMIT=${LIBTPMS_COMMIT}
ENV SWTPM_VERSION=${SWTPM_VERSION}
ENV SWTPM_COMMIT=${SWTPM_COMMIT}
ENV VIRTIOFSD_VERSION=${VIRTIOFSD_VERSION}
ENV VIRTIOFSD_COMMIT=${VIRTIOFSD_COMMIT}

# ---------------------------------------------------------------------------
# Base build toolchain
# ---------------------------------------------------------------------------
RUN set -eux; \
    apt-get update; \
    apt-get install --yes --no-install-recommends \
        autoconf automake build-essential ca-certificates cmake curl file \
        gettext git libglib2.0-dev-bin libaio-dev libattr1-dev \
        libcap-ng-dev libcurl4-openssl-dev libepoxy-dev libfdt-dev \
        libgbm-dev libglib2.0-dev libgnutls28-dev libjson-c-dev \
        libncurses-dev libnuma-dev libpam0g-dev libpixman-1-dev \
        libseccomp-dev libslirp-dev libspice-protocol-dev \
        libspice-server-dev libssh-dev liburing-dev libusb-1.0-0-dev \
        libusbredirparser-dev libvdeplug-dev libvirglrenderer-dev \
        meson ninja-build pkg-config python3 python3-venv \
        iproute2 libjson-glib-dev libtasn1-6-dev libtool expect gawk socat \
        ovmf seabios xz-utils; \
    rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Install Rust toolchain (needed for virtiofsd)
# ---------------------------------------------------------------------------
RUN set -eux; \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --default-toolchain stable --profile minimal; \
    . "$HOME/.cargo/env"; \
    rustup --version; \
    cargo --version

ENV PATH="/root/.cargo/bin:${PATH}"

# ---------------------------------------------------------------------------
# Build QEMU
# ---------------------------------------------------------------------------
WORKDIR /build/qemu

RUN set -eux; \
    curl -fSL "https://download.qemu.org/qemu-${QEMU_VERSION}.tar.xz" \
        -o /tmp/qemu.tar.xz; \
    echo "${QEMU_SHA256}  /tmp/qemu.tar.xz" | sha256sum --check --strict; \
    tar --strip-components=1 -xJf /tmp/qemu.tar.xz; \
    rm -f /tmp/qemu.tar.xz; \
    mkdir -p /opt/qemu/licenses; \
    cp COPYING /opt/qemu/licenses/qemu-COPYING; \
    cp COPYING.LIB /opt/qemu/licenses/qemu-COPYING.LIB; \
    cp LICENSE /opt/qemu/licenses/qemu-LICENSE

RUN set -eux; \
    ./configure \
        --prefix=/opt/qemu \
        --target-list=x86_64-softmmu \
        --enable-kvm \
        --enable-linux-aio \
        --enable-linux-io-uring \
        --enable-cap-ng \
        --enable-attr \
        --enable-seccomp \
        --enable-slirp \
        --enable-libusb \
        --enable-usb-redir \
        --enable-spice \
        --enable-virglrenderer \
        --enable-vhost-net \
        --enable-vhost-user \
        --enable-vhost-vdpa \
        --enable-virtfs \
        --enable-vnc \
        --enable-curses \
        --enable-gnutls \
        --enable-libssh \
        --enable-numa \
        --enable-fdt \
        --enable-tools \
        --disable-docs \
        --disable-gtk \
        --disable-sdl \
        --disable-xen; \
    nice -n 16 make -j"$(nproc)"; \
    make install; \
    /opt/qemu/bin/qemu-system-x86_64 --version

# Also install qemu-nbd and qemu-img (they land in /opt/qemu/bin via --enable-tools)
# Verify key binaries exist
RUN set -eux; \
    test -x /opt/qemu/bin/qemu-system-x86_64; \
    test -x /opt/qemu/bin/qemu-img; \
    test -x /opt/qemu/bin/qemu-nbd

# ---------------------------------------------------------------------------
# Build libtpms (dependency for swtpm)
# ---------------------------------------------------------------------------
WORKDIR /build/libtpms

RUN set -eux; \
    git clone --depth 1 --branch "${LIBTPMS_VERSION}" \
        https://github.com/stefanberger/libtpms.git .; \
    test "$(git rev-parse HEAD)" = "${LIBTPMS_COMMIT}"; \
    ./autogen.sh --with-openssl --with-tpm2 --prefix=/opt/qemu; \
    make -j"$(nproc)"; \
    make install; \
    cp LICENSE /opt/qemu/licenses/libtpms-LICENSE

# ---------------------------------------------------------------------------
# Build swtpm
# ---------------------------------------------------------------------------
WORKDIR /build/swtpm

RUN set -eux; \
    git clone --depth 1 --branch "${SWTPM_VERSION}" \
        https://github.com/stefanberger/swtpm.git .; \
    test "$(git rev-parse HEAD)" = "${SWTPM_COMMIT}"; \
    PKG_CONFIG_PATH="/opt/qemu/lib/pkgconfig:/opt/qemu/lib/x86_64-linux-gnu/pkgconfig:${PKG_CONFIG_PATH:-}" \
    ./autogen.sh --prefix=/opt/qemu --with-openssl; \
    make -j"$(nproc)"; \
    make install; \
    cp COPYING /opt/qemu/licenses/swtpm-COPYING; \
    cp LICENSE /opt/qemu/licenses/swtpm-LICENSE

RUN set -eux; \
    test -x /opt/qemu/bin/swtpm; \
    LD_LIBRARY_PATH=/opt/qemu/lib:/opt/qemu/lib/x86_64-linux-gnu \
        /opt/qemu/bin/swtpm --version

# ---------------------------------------------------------------------------
# Build virtiofsd (Rust implementation)
# ---------------------------------------------------------------------------
WORKDIR /build/virtiofsd

RUN set -eux; \
    git clone --depth 1 --branch "${VIRTIOFSD_VERSION}" \
        https://gitlab.com/virtio-fs/virtiofsd.git .; \
    test "$(git rev-parse HEAD)" = "${VIRTIOFSD_COMMIT}"; \
    cargo build --release; \
    install -m 0755 target/release/virtiofsd /opt/qemu/bin/virtiofsd; \
    strip /opt/qemu/bin/virtiofsd; \
    cp LICENSE-APACHE LICENSE-BSD-3-Clause /opt/qemu/licenses/; \
    /opt/qemu/bin/virtiofsd --version

RUN test -x /opt/qemu/bin/virtiofsd

# ---------------------------------------------------------------------------
# Collect firmware files
# ---------------------------------------------------------------------------
RUN set -eux; \
    mkdir -p /opt/qemu/firmware; \
    \
    # OVMF — standard UEFI boot \
    for f in \
        /usr/share/OVMF/OVMF_CODE_4M.fd \
        /usr/share/OVMF/OVMF_CODE.fd \
        /usr/share/ovmf/OVMF.fd \
    ; do \
        if [ -f "$f" ]; then cp "$f" /opt/qemu/firmware/; fi; \
    done; \
    \
    # OVMF — Secure Boot \
    for f in \
        /usr/share/OVMF/OVMF_CODE_4M.secboot.fd \
        /usr/share/OVMF/OVMF_VARS_4M.fd \
        /usr/share/OVMF/OVMF_VARS_4M.ms.fd \
    ; do \
        if [ -f "$f" ]; then cp "$f" /opt/qemu/firmware/; fi; \
    done; \
    \
    # SeaBIOS — the QEMU build installs these under its own share dir \
    cp /opt/qemu/share/qemu/bios-256k.bin    /opt/qemu/firmware/ || true; \
    cp /opt/qemu/share/qemu/bios.bin         /opt/qemu/firmware/ || true; \
    for f in /opt/qemu/share/qemu/vgabios*.bin; do \
        [ -f "$f" ] && cp "$f" /opt/qemu/firmware/; \
    done; \
    \
    ls -la /opt/qemu/firmware/

# ---------------------------------------------------------------------------
# Bundle shared-library dependencies
# ---------------------------------------------------------------------------
COPY bundle-libs.sh /build/bundle-libs.sh
RUN chmod +x /build/bundle-libs.sh && /build/bundle-libs.sh /opt/qemu

# ---------------------------------------------------------------------------
# Create the self-extracting installer
# ---------------------------------------------------------------------------
COPY create-run-installer.sh install-qemu.sh /build/scripts/
RUN chmod +x /build/scripts/*.sh && \
    /build/scripts/create-run-installer.sh

# ---------------------------------------------------------------------------
# Final stage — only the portable installer artifact
# ---------------------------------------------------------------------------
FROM scratch AS artifact

COPY --from=build /opt/qemu/_packages/qemu-installer.run /qemu-installer.run

CMD ["/qemu-installer.run"]
