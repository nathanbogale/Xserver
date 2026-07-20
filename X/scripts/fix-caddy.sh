#!/usr/bin/env bash
set -euo pipefail
CADDYFILE="/etc/caddy/Caddyfile"
SNIPPET="$(dirname "$0")/../caddy-x.conf"

sudo cp "$CADDYFILE" "${CADDYFILE}.bak.$(date +%s)"

# Remove all Nextcloud/Office/Whiteboard blocks (http and https forms, old collabora name)
while sudo grep -qE '(http://)?(x|docs\.x|collabora\.x|whiteboard\.x)\.decentral\.technology' "$CADDYFILE"; do
  sudo sed -i '/\(http:\/\/\)\?\(x\|docs\.x\|collabora\.x\|whiteboard\.x\)\.decentral\.technology/,/^}/d' "$CADDYFILE"
done

# Remove leftover snippet comments
sudo sed -i '/# Add these blocks to \/etc\/caddy\/Caddyfile/d' "$CADDYFILE"
sudo sed -i '/#   sudo caddy validate/d' "$CADDYFILE"
sudo sed -i '/#   sudo systemctl reload caddy/d' "$CADDYFILE"

# Append clean blocks once
echo "" | sudo tee -a "$CADDYFILE" > /dev/null
sudo tee -a "$CADDYFILE" < "$SNIPPET" > /dev/null

sudo caddy validate --config "$CADDYFILE"
sudo systemctl reload caddy
echo "Caddy fixed: x.decentral.technology + docs.x.decentral.technology + whiteboard.x.decentral.technology"
