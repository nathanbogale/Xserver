#!/usr/bin/env bash
set -euo pipefail
SNIPPET="$(dirname "$0")/../caddy-snippet.conf"
if ! grep -q 'x.decentral.technology' /etc/caddy/Caddyfile 2>/dev/null; then
  sudo tee -a /etc/caddy/Caddyfile < "$SNIPPET" > /dev/null
fi
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
echo "Caddy reloaded for x.decentral.technology"
