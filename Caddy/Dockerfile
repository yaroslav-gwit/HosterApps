FROM golang:1.25 AS build

ARG DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------------
# Version pins — update these to bump the build.
# ---------------------------------------------------------------------------
ENV CADDY_VERSION=v2.11.2
ENV XCADDY_VERSION=v0.4.5

# ---------------------------------------------------------------------------
# Install xcaddy
# ---------------------------------------------------------------------------
RUN set -eux; \
    go install github.com/caddyserver/xcaddy/cmd/xcaddy@${XCADDY_VERSION}

# ---------------------------------------------------------------------------
# Build Caddy with Cloudflare DNS and SSH modules
# ---------------------------------------------------------------------------
WORKDIR /build

# Note: the SSH module is currently disabled because we need to fork it
# and make the API more stable before we can include it in the build. Once that's done, we can re-enable it.
# --with github.com/mohammed90/caddy-ssh; \

RUN set -eux; \
    xcaddy build ${CADDY_VERSION} \
        --with github.com/caddy-dns/cloudflare; \
    ./caddy version; \
    ./caddy list-modules | grep -E 'cloudflare' || true

# ---------------------------------------------------------------------------
# Create the self-extracting installer
# ---------------------------------------------------------------------------
COPY create-run-installer.sh install-caddy.sh /build/scripts/
RUN chmod +x /build/scripts/*.sh && \
    CADDY_BINARY=/build/caddy /build/scripts/create-run-installer.sh

# ---------------------------------------------------------------------------
# Final stage — only the portable installer artifact
# ---------------------------------------------------------------------------
FROM scratch AS artifact

COPY --from=build /build/_packages/caddy-installer.run /caddy-installer.run

CMD ["/caddy-installer.run"]
