FROM ubuntu:24.04 AS build

ARG DEBIAN_FRONTEND=noninteractive
ENV LC_ALL=C.UTF-8
ENV SAUNAFS_VERSION=v5.7.1
ENV VCPKG_ROOT=/opt/vcpkg
ENV PATH="${VCPKG_ROOT}:${PATH}"

# This Dockerfile is intended to live in a tiny standalone "build-only" repo.
# It clones SaunaFS itself, checks out a fixed tag, and emits only the final
# self-extracting installer artifact.
WORKDIR /build-tools

COPY create-run-installer.sh install-bundle.sh install-layout-common.sh install-system.sh ./

# Clone the upstream source and then use its maintained dependency installer.
RUN set -eux; \
    apt-get update; \
    apt-get install --yes ca-certificates git lsb-release unzip zip; \
    git clone https://github.com/leil-io/saunafs.git /saunafs; \
    git -C /saunafs checkout "${SAUNAFS_VERSION}"; \
    bash /saunafs/tests/install-packages.sh; \
    git clone https://github.com/microsoft/vcpkg.git "${VCPKG_ROOT}"; \
    "${VCPKG_ROOT}/bootstrap-vcpkg.sh" -disableMetrics; \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

WORKDIR /saunafs

# SaunaFS needs vcpkg-managed dependency versions such as fmt with fmt/base.h.
RUN set -eux; \
    vcpkg install; \
    mkdir build; \
    cd build; \
    cmake \
        -DCMAKE_INSTALL_PREFIX=/ \
        -DCMAKE_TOOLCHAIN_FILE="${VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake" \
        -DCMAKE_EXE_LINKER_FLAGS="-static-libstdc++ -static-libgcc" \
        -DCMAKE_SHARED_LINKER_FLAGS="-static-libgcc" \
        ..; \
    nice -n 16 make -j"$(nproc)"; \
    PROJECT_DIR=/saunafs BUILD_DIR=/saunafs/build /build-tools/create-run-installer.sh

# Final stage contains only the portable installer artifact. This makes it easy
# to export with either `docker build --output` (BuildKit) or `docker cp`.
FROM scratch AS artifact

COPY --from=build /saunafs/_packages/saunafs-installer.run /saunafs-installer.run

# Having a default command makes `docker create saunafs-installer` work without
# needing to pass an explicit placeholder command before `docker cp`.
CMD ["/saunafs-installer.run"]
