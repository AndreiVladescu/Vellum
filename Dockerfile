# Vellum sync server (plan 5 #36).
#
# Multi-stage: build with the Rust toolchain, ship a slim Debian runtime.
# Deliberately **not** `scratch` or `distroless`, even though the server is a
# single static binary — its PDF cover/text extraction is a best-effort shell-out
# to whatever CLI the host has (see DESIGN.md), and an image with no userland
# would silently lose that. `poppler-utils` is what makes the fallback work.

FROM rust:1-bookworm AS build
WORKDIR /src

# Cache dependencies separately from the source: a code-only change then reuses
# the compiled dependency layer instead of rebuilding the world.
COPY server/Cargo.toml server/Cargo.lock ./
RUN mkdir src && echo 'fn main() {}' > src/main.rs && \
    echo '' > src/lib.rs && \
    cargo build --release --locked && \
    rm -rf src

COPY server/ ./
# `touch` so cargo doesn't reuse the placeholder's fingerprint for the real
# sources copied above.
RUN touch src/main.rs src/lib.rs && cargo build --release --locked

FROM debian:bookworm-slim AS runtime

# ca-certificates: the server fetches metadata and covers over HTTPS.
# poppler-utils: pdftoppm/pdftotext for cover rendering and text extraction.
# curl: only so HEALTHCHECK can actually probe /health (see below).
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates poppler-utils curl && \
    rm -rf /var/lib/apt/lists/*

# A dedicated unprivileged user; the data volume is chowned to it below.
RUN useradd --system --uid 10001 --home /var/lib/vellum --create-home vellum

COPY --from=build /src/target/release/vellum-server /usr/local/bin/vellum-server

ENV VELLUM_DB=/var/lib/vellum/vellum.db \
    VELLUM_DATA_DIR=/var/lib/vellum/data \
    VELLUM_PORT=3000 \
    RUST_LOG=info

# One volume for both the database and the blobs: they must be backed up
# together (a database referencing files that aren't in the same snapshot is
# exactly the inconsistency the library doctor exists to find).
VOLUME ["/var/lib/vellum"]
WORKDIR /var/lib/vellum
USER vellum
EXPOSE 3000

# /health is unauthenticated and cheap by design, which is what makes it usable
# here. It has to be a *request*: running the binary with `--version` would
# report healthy even with the server process dead, which is worse than no
# health check at all.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -fsS "http://127.0.0.1:${VELLUM_PORT}/health" || exit 1

ENTRYPOINT ["/usr/local/bin/vellum-server"]
