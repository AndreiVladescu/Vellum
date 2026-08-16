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

### Docker Compose

One `docker-compose.yml`, two shapes. Which you want depends on whether you
already run a reverse proxy.

**Just the server, behind your own proxy** — nginx, HAProxy, Traefik, a Caddy
you manage yourself:

```sh
printf 'VELLUM_PUBLIC_URL=https://books.example.com\n' > .env
docker compose up -d
```

That publishes **127.0.0.1:3000 and nothing else**, so only something on the
same host can reach it. Point your proxy there.
`packaging/nginx.conf.example` is a working server block; the two settings in it
that are not boilerplate are `client_max_body_size` (nginx rejects a large book
long before `VELLUM_MAX_UPLOAD_MB` is consulted) and `X-Forwarded-For` (without
it every request looks like it came from the proxy, so one impatient client
throttles everybody).

`VELLUM_BIND` is the whole left-hand side of the ports mapping, so it sets both
the interface and the port you reach the container on: `127.0.0.1:3200` moves it
to 3200 on loopback, `0.0.0.0:3000` exposes it to a proxy on another machine.
Only do the latter on a network you trust — that port is unencrypted.

Note that `VELLUM_PORT` is the wrong knob here: the mapping fixes the port
*inside* the container at 3000, and that variable is deliberately not passed
through, so setting it in `.env` does nothing under Docker.

**With Caddy, for automatic TLS** — a public domain and no existing proxy:

```sh
printf 'DOMAIN=books.example.com\nACME_EMAIL=you@example.com\n' > .env
docker compose --profile caddy up -d
```

Caddy obtains and renews a Let's Encrypt certificate by itself. Its config
(`packaging/Caddyfile`) gets the same two details right.

Either way Vellum never sees a certificate — whatever is in front terminates
TLS. Don't also set `VELLUM_TLS`; running two certificate stories at once means
debugging both.

`VELLUM_PUBLIC_URL` is what public share links embed, so it has to be the
address people actually reach. Setting `DOMAIN` derives it as
`https://$DOMAIN`; set `VELLUM_PUBLIC_URL` directly for anything else — a
non-standard port, a subpath, or plain http on a LAN. With neither set the
server starts on `http://localhost:3000` and says so at boot with a warning —
every link it hands out then works only for someone sitting on that machine.

Compose used to refuse to parse instead, via a `${DOMAIN:?…}` guard. That is
gone: some versions interpolate the whole file up front, including the default
branch that is not taken, so the guard fired with *"required variable DOMAIN is
missing a value"* even for people who had correctly set `VELLUM_PUBLIC_URL` and
never wanted `DOMAIN` at all.

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

#### Making the certificate yourself, with openssl

`VELLUM_TLS=1` already generates one, and that is the easy path. Do this instead
when the certificate has to outlive the data directory, cover names the server
was never told about, or be signed by a CA your devices already trust. An
existing `cert.pem`/`key.pem` pair is always preferred over generating one, so
putting your own in place is the whole installation step.

```sh
openssl req -x509 -newkey rsa:2048 -sha256 -days 397 -nodes \
  -keyout key.pem -out cert.pem \
  -subj "/CN=vellum.lan" \
  -addext "subjectAltName=DNS:vellum.lan,DNS:localhost,IP:127.0.0.1,IP:192.168.1.50" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature,keyEncipherment" \
  -addext "extendedKeyUsage=serverAuth"
```

- **`subjectAltName` is the part that matters.** Every current client ignores the
  common name entirely and matches only against the SANs, so a certificate
  without them fails everywhere for reasons that look like nothing at all. List
  every address you will actually type — the LAN IP, the hostname, `localhost`
  — because adding one later means issuing a new certificate.
- **`-days 397`** rather than something comfortable: Apple platforms reject a
  server certificate whose lifetime exceeds 398 days, and they reject it at
  connection time, months after you made it.
- **`-nodes`** leaves the key without a passphrase, which is what lets the server
  start unattended.
- Elliptic curve works too — `-newkey ec -pkeyopt ec_paramgen_curve:P-256`.
  PKCS#8 (`BEGIN PRIVATE KEY`), PKCS#1 (`BEGIN RSA PRIVATE KEY`) and SEC1 keys
  all load, so no conversion step is needed whichever way you generated it.

Point the server at the pair:

```sh
VELLUM_TLS=1 \
VELLUM_TLS_CERT=/var/lib/vellum/cert.pem \
VELLUM_TLS_KEY=/var/lib/vellum/key.pem \
vellum-server
```

The key must be readable by the user the server runs as, and by nobody else —
under systemd that is `vellum`:

```sh
sudo install -o vellum -g vellum -m 600 key.pem  /var/lib/vellum/key.pem
sudo install -o vellum -g vellum -m 644 cert.pem /var/lib/vellum/cert.pem
```

Check what you made, and what the app is about to be asked to trust:

```sh
openssl x509 -in cert.pem -noout -subject -dates -ext subjectAltName
openssl x509 -in cert.pem -noout -fingerprint -sha256
```

That fingerprint is the one the server prints at startup and the one the app's
server screen shows before you import — three places that must agree. Replacing
the certificate changes it, so every app that pinned the old one asks again.

**A private CA** is worth the extra step once more than one device is involved:
trust `ca.pem` once per device and every certificate you sign with it is
accepted, including future ones.

```sh
# 1. The CA. Once, and keep ca-key.pem somewhere safe — it can sign anything.
openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
  -keyout ca-key.pem -out ca.pem -subj "/CN=Vellum home CA" \
  -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
  -addext "keyUsage=critical,keyCertSign,cRLSign"

# 2. A key and a signing request for the server.
openssl req -newkey rsa:2048 -sha256 -nodes \
  -keyout key.pem -out server.csr -subj "/CN=vellum.lan"

# 3. Sign it. The extensions go here, not in the request: openssl drops a CSR's
#    own extensions unless told otherwise, which is how CA-signed certificates
#    end up with no SANs.
cat > ext.cnf <<'EOF'
subjectAltName=DNS:vellum.lan,DNS:localhost,IP:127.0.0.1,IP:192.168.1.50
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
EOF
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial \
  -sha256 -days 397 -out cert.pem -extfile ext.cnf

openssl verify -CAfile ca.pem cert.pem      # says: cert.pem: OK
```

Serve `cert.pem`/`key.pem` as above and install `ca.pem` on each device — the
system trust store on a desktop, *Settings → Security → Install a certificate →
CA certificate* on Android. `ca-key.pem` never leaves your machine.

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
authority if this table drifts. To configure a server by editing a file rather
than by exporting variables one at a time, copy **`server/.env.example`** — the
same list, commented out at its defaults — to `server/.env` and source it.

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
| `VELLUM_LOGIN_MAX_FAILURES` | `10` | Failed logins per email/IP per 15 minutes before throttling; `0` disables it |
| `RUST_LOG` | `info` | Log filter, e.g. `vellum_server=debug` |

### Content search (optional)

Off unless switched on. When enabled, the server extracts the text of every
uploaded PDF and EPUB into an FTS5 index and serves `GET /api/search`; the app
grows an "In book contents" tab and the console a "Search inside books" button,
both revealed by `GET /api/capabilities`.

| Variable | Default | Meaning |
|---|---|---|
| `VELLUM_INDEX_TEXT` | off | `1`/`true` indexes book contents for search |

What it costs, plainly: **the index is roughly the size of the text it holds** —
a few megabytes per thousand-page technical book, far less for novels — on top
of the blobs themselves. It can be dropped and rebuilt at any time
(`POST /api/admin/reindex`, master only); nothing in it is a source of truth.
Extraction runs in a background worker, one file at a time, so it never competes
with serving requests, and a server restarted mid-run resumes where it stopped.

Switching it on is **retroactive**: the backlog is queued at the next startup,
so an existing library is indexed rather than only future uploads.

A scanned PDF with no text layer records `no_text` and is simply not searchable.
There is **no OCR** and there will not be — a tesseract dependency contradicts
the single-binary story the rest of this server is built around.

### Reading in the browser

Always on, no configuration. `/read/<book id>` reads a book from the console (an
EPUB as sanitised HTML, a PDF as rendered page images); `/r/<share token>` does
the same for anyone with a public link, **read-only** — a public reader may read
the book but not take the file.

Page images are cached under `<data>/pages/`, so the directory grows with how
much of your PDFs people actually read. It is pure cache: delete it whenever you
like and pages re-render on demand.

Reading a share link does **not** consume its `max_uses`. That counts downloads —
a one-time link exists so a file can be handed over once, and spending it on a
page turn would destroy the link the moment someone opened the book.

### Activity log (optional)

Off unless switched on. When enabled, every mutation (book create/update/delete,
file upload, user creation, share create/revoke) writes a row naming the actor,
the action, the target and a short label — never a payload. The console's
**Activity** button reads it; only the master account can.

| Variable | Default | Meaning |
|---|---|---|
| `VELLUM_AUDIT` | off | `1`/`true` records who changed what |

Bounded on purpose: the oldest rows are trimmed beyond 50,000, so an unattended
server cannot fill its disk with a log. Writes are best-effort — a failed audit
row is logged and ignored rather than failing the request the user asked for.

### Email (optional)

Off unless configured — a LAN server needs no mailer, and the app hides the
features that would need one (it learns this from `GET /api/capabilities`).

| Variable | Default | Meaning |
|---|---|---|
| `VELLUM_SMTP_HOST` | — | SMTP server; setting it turns mail on |
| `VELLUM_SMTP_PORT` | `587` | Submission port, STARTTLS |
| `VELLUM_SMTP_USER` | — | Username, if the relay wants one |
| `VELLUM_SMTP_PASS` | — | Password |
| `VELLUM_MAIL_FROM` | — | Sender address; **required** once the host is set |

For Gmail: `smtp.gmail.com`, port 587, and an **App Password** — which needs
2-step verification on the account, and is not your normal password. A
misconfiguration (bad port, missing `VELLUM_MAIL_FROM`) stops the server at
startup rather than surfacing later as a password reset that silently fails.

**In Docker, setting these in `.env` is not enough on its own.** Compose reads
that file only to substitute `${...}` inside `docker-compose.yml`; the container
gets exactly the variables the compose file names under `environment:`. All five
are named there, so an ordinary `.env` works — but a *modified* compose file that
drops one will silently disable mail, and `server/tests/compose_env.rs` exists to
fail the build when that happens. After editing `.env`, recreate the container
(`docker compose up -d`) rather than restarting it: a restart keeps the
environment the container was created with.

Once it is running, check it from the console rather than by inviting somebody:
**People → Send me a test** sends to your own address and shows the relay's own
refusal if there is one — `535 5.7.8 Username and Password not accepted` names
the variable to fix, where "could not send the email" does not. The same strip
says *Email is off* with a summary of these variables when nothing is set.

#### Sending books to an e-reader

With mail configured, the server also advertises `send_to_device` and the app's
book toolbar gains **Send to a device** (plan 5 #53). One step is easy to miss
and is not something Vellum can do for you:

> **The recipient service must approve your sender address.** Amazon only
> accepts a document from an address on the account's *Approved Personal
> Document E-mail List* — add whatever `VELLUM_MAIL_FROM` is, at
> *Manage Your Content and Devices → Preferences → Personal Document Settings*.
> Kobo and PocketBook have the same idea under different names. Until that is
> done, every send is refused **by the recipient**, not by Vellum, and the app
> shows the relay's refusal.

Two other limits worth knowing:

- **25 MB per book.** Enforced by Vellum before anything is sent, because
  base64 inflates an attachment by about a third and most services stop at
  50 MB. A larger book is refused with its size rather than accepted and lost.
- **The file's extension decides the conversion.** Send-to-Kindle reads the
  suffix, so books are attached as `Title.epub` / `Title.pdf`. EPUB is offered
  first where a book has both — Kindle has accepted EPUB since 2022, and a PDF
  arrives unconverted and is usually unreadable on a small screen.

Sends are rate-limited per user, like metadata lookups: outbound mail is a
shared, quota'd resource, and a loop over a whole library looks like abuse from
the relay's side.

**`VELLUM_PUBLIC_URL` matters.** Public share links embed it; if it says
`localhost`, that is what the links will say.

**`VELLUM_BOOTSTRAP_TOKEN` matters on a public host.** The first account to
register becomes the master. Without a bootstrap token, whoever reaches a fresh
server first gets it.

---

## First run

1. Start the server.
2. Open `http://<host>:<port>/` — the web console.
3. Register. A server with no accounts opens on the *Create the master account*
   form rather than a login box (and asks for the bootstrap token when one is
   set). **The first account is the master**; afterwards registration is closed,
   the console goes back to logging in, and the master provisions member
   accounts.
4. In the app: *Library server* → the same URL → sign in. On a self-signed
   setup, import the certificate when prompted.

---

## Backups

**The supported way is one request** (plan 5 #12). `GET /api/admin/snapshot`
streams a `.tar` containing a consistent copy of the database plus every cover
and book file:

```sh
curl -fL -H "Authorization: Bearer $TOKEN" \
     -o "vellum-$(date +%F).tar" \
     https://books.example.com/api/admin/snapshot
```

As a cron line:

```cron
17 3 * * * curl -fsSL -H "Authorization: Bearer $VELLUM_TOKEN" \
  -o /backups/vellum-$(date +\%F).tar https://books.example.com/api/admin/snapshot
```

It is master-only, and it uses SQLite's `VACUUM INTO` — which produces a
consistent single-file copy **without touching the live WAL**. That is exactly
the trap in doing it by hand: copying a `.db` while it is being written restores
to a database that is subtly wrong rather than obviously broken. The archive is
assembled on disk before streaming, so the host needs transient free space of
roughly the library's size.

To check what a running server thinks of its own storage first:

```sh
curl -H "Authorization: Bearer $TOKEN" .../api/admin/sweep -X POST
```

reports rows whose blobs are missing and blobs no row references, and **deletes
nothing** unless you add `?delete_orphans=true`.

Stopping the container and archiving the volume also works, and needs no token:

```sh
docker compose stop vellum
docker run --rm -v vellum-data:/data -v "$PWD:/out" debian:stable-slim \
  tar czf /out/vellum-backup.tar.gz -C /data .
docker compose start vellum
```

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

---

## Working on the server

Some queries are **compile-checked** against the schema (plan 5 #46): they use
`sqlx::query!`-family macros, verified at build time from the committed
`server/.sqlx/` data. That means no database is needed to build.

After editing or adding such a query, regenerate the data:

```sh
cd server
export DATABASE_URL="sqlite://$PWD/prepare.db?mode=rwc"
sqlx database create && sqlx migrate run
cargo sqlx prepare -- --lib
rm -f prepare.db*
```

CI fails if `.sqlx/` is out of date. Queries composed with `format!` (the
visibility predicate, the dynamic-table helpers) can't use the macros — they take
a string literal — so the migration is deliberately incremental, module by
module.
