# Vellum server

[Vellum](https://github.com/AndreiVladescu/Vellum) is a personal library manager
for digital (PDF/EPUB) and physical books, shown as a visual bookshelf. The app
works fully offline on its own; this image is the **optional sync server** that
shares one library across devices and people. Licence: AGPL-3.0.

Images are published for `linux/amd64` and `linux/arm64` (Raspberry Pi 4/5
included). Tags: `X.Y.Z`, `X.Y` and `latest`.

## Quick start

```sh
docker run -d --name vellum \
  -p 3000:3000 \
  -v vellum-data:/var/lib/vellum \
  -e VELLUM_PUBLIC_URL=http://localhost:3000 \
  --restart unless-stopped \
  VELLUM_DOCKERHUB_NAMESPACE/vellum-server
```

Then open <http://localhost:3000/> and create the master account (the first
account to register becomes the master).

## Docker Compose

```yaml
services:
  vellum:
    image: VELLUM_DOCKERHUB_NAMESPACE/vellum-server:latest
    restart: unless-stopped
    environment:
      VELLUM_PUBLIC_URL: https://books.example.com
    volumes:
      - vellum-data:/var/lib/vellum
    ports:
      - "127.0.0.1:3000:3000"

volumes:
  vellum-data:
```

The database and the book files both live under `/var/lib/vellum`; back them up
together. Put a reverse proxy in front for TLS (a phone's Android app refuses
plain http to anything but localhost).

The same image is on GitHub Container Registry as
`ghcr.io/andreivladescu/vellum-server`.

## Documentation

Reverse proxy and automatic TLS, self-signed LAN certificates, every
environment variable, email, backups and upgrades:
**<https://github.com/AndreiVladescu/Vellum/blob/main/docs/DEPLOYMENT.md>**
