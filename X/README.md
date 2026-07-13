# X — Nextcloud Team Server

Self-hosted Nextcloud for the Decentral team at **http://x.decentral.technology**

## Quick start

```bash
cd /home/server/X
docker-compose up -d
```

## One-time: apply Caddy reverse proxy

Requires sudo:

```bash
./scripts/apply-caddy.sh
```

Or manually append `caddy-snippet.conf` to `/etc/caddy/Caddyfile` and run `sudo systemctl reload caddy`.

## URLs

| Service | URL |
|---------|-----|
| Nextcloud | http://x.decentral.technology |
| Collabora (Office) | http://collabora.x.decentral.technology |

## Ports (host)

| Port | Service |
|------|---------|
| 8300 | Nextcloud (localhost, via Caddy) |
| 8301 | Collabora (localhost, via Caddy) |
| 8302 | Coturn TURN (UDP/TCP) |
| 8303–8320 | Coturn media relay (UDP) |

## Admin login

Credentials are in `.env` (chmod 600):

- User: `admin` (or `NEXTCLOUD_ADMIN_USER`)
- Password: `NEXTCLOUD_ADMIN_PASSWORD`

## Enabled apps

- Calendar, Contacts, Talk (video), Deck, Notes, Tasks, Team Folders, Mail, Office (Collabora)

## Add team members

```bash
docker-compose exec -u www-data app php occ user:add alice
docker-compose exec -u www-data app php occ group:add engineering
docker-compose exec -u www-data app php occ group:adduser engineering alice
```

## Maintenance

```bash
# Update images
docker-compose pull && docker-compose up -d

# Upgrade Nextcloud after image update
docker-compose exec -u www-data app php occ upgrade

# Backup: ./data volume, db_data volume, and .env
```
