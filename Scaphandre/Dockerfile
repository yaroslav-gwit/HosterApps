FROM rust:1.95-alpine AS build

ARG SCAPHANDRE_VERSION=v1.0.3
ARG SCAPHANDRE_COMMIT=b64443c447e24f25947111ec8611449f213eb0a5

# ---------------------------------------------------------------------------
# Version pins — update both values together when bumping the build.
# ---------------------------------------------------------------------------
ENV SCAPHANDRE_VERSION=${SCAPHANDRE_VERSION}
ENV SCAPHANDRE_COMMIT=${SCAPHANDRE_COMMIT}
ENV OPENSSL_STATIC=1

# Scaphandre is built against musl so the release does not depend on the
# target host's glibc or OpenSSL versions.
RUN set -eux; \
	apk add --no-cache \
		binutils git make musl-dev openssl-dev openssl-libs-static perl pkgconf; \
	test "$(uname -m)" = x86_64

WORKDIR /build/scaphandre

RUN set -eux; \
	git clone --depth 1 --branch "${SCAPHANDRE_VERSION}" \
		https://github.com/hubblo-org/scaphandre.git .; \
	test "$(git rev-parse HEAD)" = "${SCAPHANDRE_COMMIT}"

# The v1.0.3 tag accidentally retained 1.0.2 in Cargo.toml/Cargo.lock. Patch
# only the package's own version so `scaphandre --version` matches the tag.
RUN set -eux; \
	release_version="${SCAPHANDRE_VERSION#v}"; \
	sed -i 's/^version = "1\.0\.2"/version = "'"${release_version}"'"/' Cargo.toml; \
	sed -i '/name = "scaphandre"/{n;s/^version = ".*"/version = "'"${release_version}"'"/;}' Cargo.lock; \
	cargo build --release --locked --no-default-features \
		--features prometheus,containers,qemu,json; \
	strip target/release/scaphandre; \
	target/release/scaphandre --version; \
	if readelf --program-headers target/release/scaphandre | grep -q ' INTERP '; then \
		echo 'Scaphandre binary is not statically linked' >&2; \
		exit 1; \
	fi

# The installer generator and the emitted installer use Bash. Keep it out of
# the compilation layer so packaging-only changes retain the Rust build cache.
RUN apk add --no-cache bash

# ---------------------------------------------------------------------------
# Create the self-extracting installer
# ---------------------------------------------------------------------------
COPY create-run-installer.sh install-scaphandre.sh scaphandre.service /build/scripts/
RUN chmod +x /build/scripts/*.sh && \
	SCAPHANDRE_BINARY=/build/scaphandre/target/release/scaphandre \
	SCAPHANDRE_VERSION="${SCAPHANDRE_VERSION}" \
	SCAPHANDRE_COMMIT="${SCAPHANDRE_COMMIT}" \
	/build/scripts/create-run-installer.sh

# ---------------------------------------------------------------------------
# Final stage — only the portable installer artifact
# ---------------------------------------------------------------------------
FROM scratch AS artifact

COPY --from=build /build/_packages/scaphandre-installer.run /scaphandre-installer.run

CMD ["/scaphandre-installer.run"]
