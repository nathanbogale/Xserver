#!/usr/bin/env bash
# Install apps from nextcloud-releases when the app store API is unavailable.
set -euo pipefail
cd "$(dirname "$0")/.."
TMP=/tmp/nc-apps-install
mkdir -p "$TMP" /home/server/X/custom_apps
install_release() {
  local repo="$1" tag="$2"
  local url
  url=$(curl -fsSL "https://api.github.com/repos/nextcloud-releases/${repo}/releases/tags/${tag}" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['assets'][0]['browser_download_url'])")
  curl -fsSL -o "$TMP/${repo}.tar.gz" "$url"
  tar -xzf "$TMP/${repo}.tar.gz" -C "$TMP"
  docker run --rm -v "$TMP:/src" -v /home/server/X/custom_apps:/target alpine sh -c "rm -rf /target/${repo}; cp -a /src/${repo} /target/"
  docker-compose exec -T app chown -R www-data:www-data "/var/www/html/custom_apps/${repo}"
  docker-compose exec -T -u www-data app php occ app:enable "$repo" || \
    docker-compose exec -T -u www-data app php occ app:install "$repo" --force
}
# NC 34 compatible release tags
install_release calendar v6.5.0
install_release contacts v8.7.3
for repo in spreed deck notes groupfolders mail richdocuments; do
  tag=$(curl -fsSL "https://api.github.com/repos/nextcloud-releases/${repo}/releases/latest" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])")
  install_release "$repo" "$tag"
done
docker-compose exec -T -u www-data app php occ config:app:set richdocuments wopi_url --value="https://docs.x.decentral.technology"
docker-compose exec -T -u www-data app php occ config:app:set richdocuments public_wopi_url --value="https://docs.x.decentral.technology"
docker-compose exec -T -u www-data app php occ config:app:set richdocuments wopi_allowlist --value="172.16.0.0/12,10.0.0.0/8,127.0.0.1"
# Set callback after any activate-config; activate-config resets wopi_callback_url to autodetect
docker-compose exec -T -u www-data app php occ config:app:set richdocuments wopi_callback_url --value="http://app"
echo "Done."
