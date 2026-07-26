# Deploying the Vellum server

The server is **optional**. The app is local-first and works fully offline
without one; a server exists to share one library across devices and people.

It is a single static binary plus one directory. Everything is configured by
environment variables — there is no config file, and there won't be one.

---

## Which option is yours

| Situation | Use |
|---|---|
| A domain name, reachable from the internet | [Docker Compose with Caddy](#docker-compose-with-automatic-tls) — automatic Let's Encrypt TLS |
| A machine on your LAN, no domain | [The binary or the image with `VELLUM_TLS=1`](#lan-only-self-signed-tls) — self-signed cert you import into the app |
| A Linux box you already manage | [systemd unit](#systemd) |
| Just trying it out | `cargo run` in `server/`, or `docker run` below |

The Android app **refuses cleartext HTTP** to anything but localhost, so a phone
needs one of the TLS options.

---

## Docker

```sh
docker build -t vellum-server .
docker run -d --name vellum \
  -p 3000:3000 \
  -v vellum-data:/var/lib/vellum \
  -e VELLUM_PUBLIC_URL=http://localhost:3000 \
  vellum-server
```

The image runs as an unprivileged user (uid 10001) and keeps the database *and*
the blobs under one volume, `/var/lib/vellum` — they must be backed up together,
since a database referencing files that aren't in the same snapshot is exactly
the inconsistency the app's library health check exists to find.

It is built on `debian-slim` rather than `scratch` on purpose: the server's PDF
cover rendering and text extraction are a best-effort shell-out to
`pdftoppm`/`pdftotext` (see `DESIGN.md`), and an image with no userland would
silently lose that. `poppler-utils` is installed for exactly that reason.

`/health` is unauthenticated and cheap; the image's `HEALTHCHECK` uses it.

### Docker Compose with automatic TLS

`docker-compose.yml` runs Vellum behind Caddy, which obtains and renews a
certificate for you.

```sh
printf 'DOMAIN=books.example.com\nACME_EMAIL=you@example.com\n' > .env
docker compose up -d
```

Vellum itself never sees a certificate here — Caddy terminates TLS and forwards
plain HTTP on an internal network. Don't also set `VELLUM_TLS`; running two
certificate stories at once means debugging both.

Caddy's config (`packaging/Caddyfile`) raises the request body limit to 2 GB and
forwards `X-Forwarded-For`, which the server's per-IP rate limiting reads.

### LAN-only, self-signed TLS

No domain, no ACME. The server generates and reuses its own certificate:

```sh
docker run -d --name vellum \
  -p 3000:3000 -v vellum-data:/var/lib/vellum \
  -e VELLUM_TLS=1 \
  -e VELLUM_TLS_SANS=192.168.1.50 \
  -e VELLUM_PUBLIC_URL=https://192.168.1.50:3000 \
  vellum-server
```

Put every address you'll connect from in `VELLUM_TLS_SANS`. The certificate is
written under the data dir and **persists across restarts**, so the fingerprint
the app pinned stays valid; delete `cert.pem`/`key.pem` to rotate. The app's
server screen shows the fingerprint and offers to import the certificate.

---

## systemd

For a bare-metal install:

```sh
sudo useradd --system --home /var/lib/vellum --create-home vellum
sudo install -m755 vellum-server /usr/local/bin/
sudo install -m644 packaging/vellum-server.service /etc/systemd/system/
sudo systemctl enable --now vellum-server
```

The unit runs as a dedicated user with `ProtectSystem=strict`,
`NoNewPrivileges`, a syscall filter, and write access to `/var/lib/vellum` only.
Put overrides in
`/etc/systemd/system/vellum-server.service.d/override.conf` rather than editing
the unit, so an upgrade doesn't clobber them — at minimum:

```ini
[Service]
Environment=VELLUM_PUBLIC_URL=https://books.example.com
```

---

## Configuration

`vellum-server --help` prints this list too, so the binary is always the
authority if this table drifts.

| Variable | Default | Meaning |
|---|---|---|
| `VELLUM_PORT` | `3000` | Port to listen on |
| `VELLUM_DB` | `./vellum.db` | SQLite file; migrations run at startup |
| `VELLUM_DATA_DIR` | `./data` | Covers and book files |
| `VELLUM_PUBLIC_URL` | `http://localhost:3000` | Base URL embedded in public share links |
| `VELLUM_MAX_UPLOAD_MB` | `2048` | Per-file upload cap |
| `VELLUM_TLS` | off | `1`/`true` serves HTTPS with a self-signed certificate |
| `VELLUM_TLS_CERT` | `<data>/cert.pem` | PEM certificate |
| `VELLUM_TLS_KEY` | `<data>/key.pem` | PEM key |
| `VELLUM_TLS_SANS` | — | Extra comma-separated SANs for the generated certificate |
| `VELLUM_BOOTSTRAP_TOKEN` | — | Secret the **first** (master) registration must present |
| `RUST_LOG` | `info` | Log filter, e.g. `vellum_server=debug` |

**`VELLUM_PUBLIC_URL` matters.** Public share links embed it; if it says
`localhost`, that is what the links will say.

**`VELLUM_BOOTSTRAP_TOKEN` matters on a public host.** The first account to
register becomes the master. Without a bootstrap token, whoever reaches a fresh
server first gets it.

---

## First run

1. Start the server.
2. Open `http://<host>:<port>/` — the web console.
3. Register. **The first account is the master**; afterwards registration is
   closed and the master provisions member accounts.
4. In the app: *Library server* → the same URL → sign in. On a self-signed
   setup, import the certificate when prompted.

---

## Backups

Everything is in the data directory plus the SQLite file (both under
`/var/lib/vellum` in the image):

```sh
docker compose stop vellum
docker run --rm -v vellum-data:/data -v "$PWD:/out" debian:stable-slim \
  tar czf /out/vellum-backup.tar.gz -C /data .
docker compose start vellum
```

Stopping first is the simple, always-correct option. If you can't, snapshot the
database with `sqlite3 vellum.db ".backup ..."` rather than copying the file
while it is being written — a half-copied WAL restores to a database that is
subtly wrong rather than obviously broken.

The **app** also exports a complete archive (Preferences → Backup), which is the
easier route for a single-user library.

---

## Upgrading

Migrations run automatically at startup and are forward-only:

```sh
docker compose pull && docker compose up -d   # compose
sudo systemctl restart vellum-server          # systemd
```

Back up first. There is no downgrade path — an older binary will not understand
a newer schema.

---

## Releases

Tagging `v*` builds server binaries for Linux (`x86_64`/`aarch64`, musl-static),
Windows and macOS, plus the Android app bundle and per-ABI APKs, and attaches
them to a GitHub Release with SHA-256 checksums
(`.github/workflows/release.yml`).

The Linux desktop app is still built from source
(`flutter build linux`, then `scripts/install-dev.sh`); Flatpak/AppImage/MSIX
packaging is not done yet.
