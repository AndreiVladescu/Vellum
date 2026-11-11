# Vellum sync server (plan 5 #36).
#
# Multi-stage: build with the Rust toolchain, ship a slim Debian runtime.
# Deliberately **not** `scratch` or `distroless`, even though the server is a
# single static binary — its PDF cover/text extraction is a best-effort shell-out
# to whatever CLI the host has (see DESIGN.md), and an image with no userland
# would silently lose that. `poppler-utils` is what makes the fallback work.

# The build stage always runs on the *builder's* architecture and cross-compiles
# to the image's. Building arm64 under QEMU instead takes the better part of an
# hour for a Rust release build; a cross compiler takes the same few minutes as
# a native one. Only the runtime stage below is ever executed as the target
# architecture (and then only for `apt-get`).
FROM --platform=$BUILDPLATFORM rust:1-bookworm AS build
WORKDIR /src

# Set by buildx; plain `docker build` fills them in with the host's own.
ARG BUILDARCH
ARG TARGETARCH

# Debian's name for an architecture, its GNU triple and Rust's triple differ, so
# one table maps all three. Unknown architectures fail here rather than
# producing an image that cannot start.
#
# The cross gcc matters beyond the linker: `libsqlite3-sys` (bundled SQLite) and
# `ring` both compile C, and the `cc` crate finds the compiler through the
# CC_<triple> variables below. Without them it would use the host `cc` and
# produce x86-64 objects for an arm64 link. The cross libc comes from the same
# Debian release as the runtime image, so the glibc it links against is the one
# the binary will meet.
RUN case "$TARGETARCH" in \
      amd64) echo "x86_64-unknown-linux-gnu x86-64-linux-gnu" ;; \
      arm64) echo "aarch64-unknown-linux-gnu aarch64-linux-gnu" ;; \
      *) echo "unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac > /target.txt && \
    set -- $(cat /target.txt) && \
    rustup target add "$1" && \
    if [ "$BUILDARCH" != "$TARGETARCH" ]; then \
      apt-get update && \
      apt-get install -y --no-install-recommends \
        "gcc-$2" "libc6-dev-${TARGETARCH}-cross" && \
      rm -rf /var/lib/apt/lists/*; \
    fi

# Only consulted for the target being built; the other is inert.
ENV CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc \
    CC_aarch64_unknown_linux_gnu=aarch64-linux-gnu-gcc \
    CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER=x86_64-linux-gnu-gcc \
    CC_x86_64_unknown_linux_gnu=x86_64-linux-gnu-gcc

# Cache dependencies separately from the source: a code-only change then reuses
# the compiled dependency layer instead of rebuilding the world.
COPY server/Cargo.toml server/Cargo.lock ./
RUN mkdir src && echo 'fn main() {}' > src/main.rs && \
    echo '' > src/lib.rs && \
    cargo build --release --locked --target "$(cut -d' ' -f1 /target.txt)" && \
    rm -rf src

COPY server/ ./
# `touch` so cargo doesn't reuse the placeholder's fingerprint for the real
# sources copied above. The binary is copied out of the per-target directory so
# the runtime stage does not need to know which architecture this was.
RUN touch src/main.rs src/lib.rs && \
    cargo build --release --locked --target "$(cut -d' ' -f1 /target.txt)" && \
    cp "target/$(cut -d' ' -f1 /target.txt)/release/vellum-server" /vellum-server

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

COPY --from=build /vellum-server /usr/local/bin/vellum-server

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
