FROM ubuntu:24.04 AS build

ARG DEBIAN_FRONTEND=noninteractive
ARG LEILFS_VERSION=v5.11.0
ENV LC_ALL=C.UTF-8
ENV LEILFS_VERSION=${LEILFS_VERSION}
ENV VCPKG_ROOT=/opt/vcpkg
ENV PATH="${VCPKG_ROOT}:${PATH}"

# Clone the upstream source and then use its maintained dependency installer.
RUN set -eux; \
    apt-get update; \
    apt-get install --yes ca-certificates git lsb-release unzip zip; \
    git clone --depth 1 --branch "${LEILFS_VERSION}" https://github.com/leil-io/leilfs.git /leilfs; \
    bash /leilfs/tests/install-packages.sh; \
    git clone https://github.com/microsoft/vcpkg.git "${VCPKG_ROOT}"; \
    "${VCPKG_ROOT}/bootstrap-vcpkg.sh" -disableMetrics; \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

WORKDIR /leilfs

# LeilFS needs vcpkg-managed dependency versions such as fmt with fmt/base.h.
RUN set -eux; \
    vcpkg install

# Keep compilation in its own cacheable layer. Packaging-script changes should
# not force the full dependency installation and C++ build to run again.
RUN set -eux; \
    mkdir build; \
    cd build; \
    cmake \
        -DCMAKE_INSTALL_PREFIX=/ \
        -DCMAKE_BUILD_TYPE=Release \
        -DVERSION_SUFFIX= \
        -DCMAKE_TOOLCHAIN_FILE="${VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake" \
        -DCMAKE_EXE_LINKER_FLAGS="-static-libstdc++ -static-libgcc" \
        -DCMAKE_SHARED_LINKER_FLAGS="-static-libgcc" \
        ..; \
    nice -n 16 make -j"$(nproc)"

WORKDIR /build-tools

COPY create-run-installer.sh install-bundle.sh install-layout-common.sh install-system.sh ./

RUN set -eux; \
    PROJECT_DIR=/leilfs BUILD_DIR=/leilfs/build /build-tools/create-run-installer.sh

# Final stage contains only the portable installer artifact. This makes it easy
# to export with either `docker build --output` (BuildKit) or `docker cp`.
FROM scratch AS artifact

COPY --from=build /leilfs/_packages/leilfs-installer.run /leilfs-installer.run

# Having a default command makes `docker create leilfs-installer` work without
# needing to pass an explicit placeholder command before `docker cp`.
CMD ["/leilfs-installer.run"]
