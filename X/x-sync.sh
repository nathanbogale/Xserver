#!/usr/bin/env bash
# x-sync.sh — Manage sync between host X folder and Nextcloud Team Folder X
# Usage:
#   ./x-sync.sh              # interactive menu
#   ./x-sync.sh push         # local → Nextcloud
#   ./x-sync.sh pull         # Nextcloud → local
#   ./x-sync.sh status       # show status
#   ./x-sync.sh auto-on      # enable cron auto-sync
#   ./x-sync.sh auto-off     # disable cron auto-sync
#   ./x-sync.sh auto-run     # one auto cycle (used by cron)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "${SCRIPT_DIR}/x-sync.sh")"
CONF_FILE="${SCRIPT_DIR}/x-sync.conf"
CRON_TAG="# x-sync"

# Defaults (overridden by conf)
LOCAL_DIR="/home/server/X/x"
REMOTE="nc:X"
RCLONE_REMOTE="nc"
AUTO_MODE="pull"
CRON_SCHEDULE="*/5 * * * *"
LOG_FILE="/home/server/X/x-sync.log"

if [[ -f "$CONF_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$CONF_FILE"
fi

RCLONE_FLAGS=(--progress --checkers=8 --transfers=4)
EXCLUDE_FLAGS=(
  --exclude '.git/**'
  --exclude '.git'
  --exclude '.obsidian/**'
  --exclude '.obsidian'
  --exclude '.gitignore'
  --exclude '.gitattributes'
  --exclude '.DS_Store'
  --exclude 'desktop.ini'
  --exclude 'Thumbs.db'
  --exclude '*.tmp'
  --exclude '*~'
)

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  echo "$msg" | tee -a "$LOG_FILE"
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_rclone() {
  command -v rclone >/dev/null 2>&1 || die "rclone is not installed"
  rclone listremotes 2>/dev/null | grep -qx "${RCLONE_REMOTE}:" \
    || die "rclone remote '${RCLONE_REMOTE}' not found. Run: rclone config"
}

ensure_local() {
  mkdir -p "$LOCAL_DIR"
}

header() {
  echo
  echo "=============================================="
  echo "  X Sync  |  host ↔ Nextcloud X"
  echo "=============================================="
  echo "  Local : $LOCAL_DIR"
  echo "  Remote: $REMOTE"
  echo "  Auto  : $AUTO_MODE  |  cron: $(auto_status_short)"
  echo "=============================================="
}

auto_status_short() {
  if crontab -l 2>/dev/null | grep -qF "$CRON_TAG"; then
    echo "ON"
  else
    echo "OFF"
  fi
}

cmd_status() {
  require_rclone
  ensure_local
  header
  echo
  echo "--- Local ---"
  if [[ -d "$LOCAL_DIR" ]]; then
    local count size
    count="$(find "$LOCAL_DIR" -type f ! -path '*/.git/*' 2>/dev/null | wc -l | tr -d ' ')"
    size="$(du -sh "$LOCAL_DIR" 2>/dev/null | awk '{print $1}')"
    echo "  Files (excl. .git): $count"
    echo "  Size: $size"
  else
    echo "  (missing)"
  fi
  echo
  echo "--- Nextcloud ---"
  if rclone lsd "$REMOTE" >/dev/null 2>&1 || rclone ls "$REMOTE" >/dev/null 2>&1; then
    echo "  Path OK"
    rclone size "$REMOTE" 2>/dev/null | sed 's/^/  /' || true
  else
    echo "  Path not reachable: $REMOTE"
    echo "  Tip: rclone lsd \"${RCLONE_REMOTE}:X\""
  fi
  echo
  echo "--- Auto sync ---"
  if crontab -l 2>/dev/null | grep -qF "$CRON_TAG"; then
    echo "  Enabled"
    crontab -l 2>/dev/null | grep -F "$CRON_TAG" | sed 's/^/  /'
  else
    echo "  Disabled"
  fi
  echo
  echo "--- Recent log (last 15 lines) ---"
  if [[ -f "$LOG_FILE" ]]; then
    tail -n 15 "$LOG_FILE" | sed 's/^/  /'
  else
    echo "  (no log yet)"
  fi
  echo
}

dry_run_flag() {
  if [[ "${1:-}" == "--dry-run" ]]; then
    echo "--dry-run"
  fi
}

cmd_push() {
  require_rclone
  ensure_local
  local dry
  dry="$(dry_run_flag "${1:-}")"
  log "PUSH start (local → Nextcloud) ${dry:-}"
  # shellcheck disable=SC2086
  rclone sync "$LOCAL_DIR" "$REMOTE" \
    "${RCLONE_FLAGS[@]}" \
    "${EXCLUDE_FLAGS[@]}" \
    ${dry:+$dry} \
    --log-file="$LOG_FILE" \
    --log-level INFO
  log "PUSH done"
  echo "Push complete."
}

cmd_pull() {
  require_rclone
  ensure_local
  local dry
  dry="$(dry_run_flag "${1:-}")"
  log "PULL start (Nextcloud → local) ${dry:-}"
  # shellcheck disable=SC2086
  rclone sync "$REMOTE" "$LOCAL_DIR" \
    "${RCLONE_FLAGS[@]}" \
    "${EXCLUDE_FLAGS[@]}" \
    ${dry:+$dry} \
    --log-file="$LOG_FILE" \
    --log-level INFO
  log "PULL done"
  echo "Pull complete."
}

cmd_copy_push() {
  require_rclone
  ensure_local
  log "COPY PUSH start (no deletes)"
  rclone copy "$LOCAL_DIR" "$REMOTE" \
    "${RCLONE_FLAGS[@]}" \
    "${EXCLUDE_FLAGS[@]}" \
    --log-file="$LOG_FILE" \
    --log-level INFO
  log "COPY PUSH done"
  echo "Copy push complete (destination extras kept)."
}

cmd_copy_pull() {
  require_rclone
  ensure_local
  log "COPY PULL start (no deletes)"
  rclone copy "$REMOTE" "$LOCAL_DIR" \
    "${RCLONE_FLAGS[@]}" \
    "${EXCLUDE_FLAGS[@]}" \
    --log-file="$LOG_FILE" \
    --log-level INFO
  log "COPY PULL done"
  echo "Copy pull complete (local extras kept)."
}

cmd_check() {
  require_rclone
  ensure_local
  echo "Comparing local ↔ remote (rclone check)..."
  rclone check "$LOCAL_DIR" "$REMOTE" \
    "${EXCLUDE_FLAGS[@]}" \
    --one-way \
    2>&1 | tee -a "$LOG_FILE" || true
  echo
  echo "(Exit non-zero from check usually means differences exist — that is OK.)"
}

cmd_list_remote() {
  require_rclone
  echo "Remote listing: $REMOTE"
  rclone ls "$REMOTE" 2>&1 | head -n 80
  echo "..."
  rclone size "$REMOTE" 2>&1 || true
}

cmd_list_local() {
  ensure_local
  echo "Local: $LOCAL_DIR"
  find "$LOCAL_DIR" -maxdepth 2 -type d ! -path '*/.git*' 2>/dev/null | head -n 40
  echo
  du -sh "$LOCAL_DIR" 2>/dev/null || true
}

cmd_auto_run() {
  # Non-interactive; used by cron
  require_rclone
  ensure_local
  case "$AUTO_MODE" in
    push)
      log "AUTO ($AUTO_MODE) → push"
      rclone sync "$LOCAL_DIR" "$REMOTE" \
        "${EXCLUDE_FLAGS[@]}" \
        --log-file="$LOG_FILE" \
        --log-level INFO
      ;;
    pull)
      log "AUTO ($AUTO_MODE) → pull"
      rclone sync "$REMOTE" "$LOCAL_DIR" \
        "${EXCLUDE_FLAGS[@]}" \
        --log-file="$LOG_FILE" \
        --log-level INFO
      ;;
    bisync)
      log "AUTO ($AUTO_MODE) → bisync"
      rclone bisync "$LOCAL_DIR" "$REMOTE" \
        "${EXCLUDE_FLAGS[@]}" \
        --create-empty-src-dirs \
        --resilient \
        --log-file="$LOG_FILE" \
        --log-level INFO \
        || rclone bisync "$LOCAL_DIR" "$REMOTE" \
          "${EXCLUDE_FLAGS[@]}" \
          --create-empty-src-dirs \
          --resilient \
          --resync \
          --log-file="$LOG_FILE" \
          --log-level INFO
      ;;
    *)
      die "Unknown AUTO_MODE='$AUTO_MODE' (use push|pull|bisync)"
      ;;
  esac
  log "AUTO done"
}

cmd_auto_on() {
  require_rclone
  local line
  line="${CRON_SCHEDULE} ${SCRIPT_PATH} auto-run ${CRON_TAG}"
  # Remove old entry then add
  local tmp
  tmp="$(mktemp)"
  (crontab -l 2>/dev/null | grep -vF "$CRON_TAG" || true) > "$tmp"
  echo "$line" >> "$tmp"
  crontab "$tmp"
  rm -f "$tmp"
  log "AUTO enabled: $line"
  echo "Auto-sync enabled."
  echo "  Schedule : $CRON_SCHEDULE"
  echo "  Mode     : $AUTO_MODE"
  echo "  Command  : $SCRIPT_PATH auto-run"
  echo
  echo "Edit mode/schedule in: $CONF_FILE"
  echo "Then run: $SCRIPT_PATH auto-on   (to refresh cron)"
}

cmd_auto_off() {
  local tmp
  tmp="$(mktemp)"
  (crontab -l 2>/dev/null | grep -vF "$CRON_TAG" || true) > "$tmp"
  crontab "$tmp" 2>/dev/null || crontab -r 2>/dev/null || true
  # If tmp empty, clear crontab cleanly
  if [[ ! -s "$tmp" ]]; then
    crontab -r 2>/dev/null || true
  else
    crontab "$tmp"
  fi
  rm -f "$tmp"
  log "AUTO disabled"
  echo "Auto-sync disabled."
}

cmd_set_auto_mode() {
  local mode="${1:-}"
  case "$mode" in
    push|pull|bisync) ;;
    *)
      echo "Usage: $0 set-mode push|pull|bisync"
      return 1
      ;;
  esac
  if grep -q '^AUTO_MODE=' "$CONF_FILE" 2>/dev/null; then
    sed -i "s/^AUTO_MODE=.*/AUTO_MODE=\"$mode\"/" "$CONF_FILE"
  else
    echo "AUTO_MODE=\"$mode\"" >> "$CONF_FILE"
  fi
  AUTO_MODE="$mode"
  echo "AUTO_MODE set to: $mode"
  if [[ "$(auto_status_short)" == "ON" ]]; then
    echo "Refreshing cron entry..."
    cmd_auto_on
  fi
}

cmd_edit_conf() {
  echo "Config file: $CONF_FILE"
  echo
  cat "$CONF_FILE"
  echo
  echo "Edit with: nano $CONF_FILE"
}

confirm() {
  local prompt="${1:-Continue?}"
  read -r -p "$prompt [y/N] " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]]
}

menu() {
  while true; do
    header
    cat <<'EOF'

  Manual
    1) Push  (local → Nextcloud)   [sync — can delete remote extras]
    2) Pull  (Nextcloud → local)   [sync — can delete local extras]
    3) Copy push (local → Nextcloud, no deletes)
    4) Copy pull (Nextcloud → local, no deletes)
    5) Dry-run push
    6) Dry-run pull
    7) Check differences

  Auto
    8) Enable auto-sync (cron)
    9) Disable auto-sync
   10) Set auto mode (push / pull / bisync)
   11) Run one auto cycle now

  Info
   12) Status
   13) List remote
   14) List local
   15) Show / edit config path
    0) Quit

EOF
    read -r -p "Choose: " choice
    echo
    case "$choice" in
      1)
        confirm "Push will make Nextcloud match local (may delete remote files). Continue?" \
          && cmd_push || echo "Cancelled."
        ;;
      2)
        confirm "Pull will make local match Nextcloud (may delete local files). Continue?" \
          && cmd_pull || echo "Cancelled."
        ;;
      3) cmd_copy_push ;;
      4) cmd_copy_pull ;;
      5) cmd_push --dry-run ;;
      6) cmd_pull --dry-run ;;
      7) cmd_check ;;
      8) cmd_auto_on ;;
      9) cmd_auto_off ;;
      10)
        read -r -p "Mode [push|pull|bisync] (current: $AUTO_MODE): " m
        cmd_set_auto_mode "$m" || true
        ;;
      11) cmd_auto_run ;;
      12) cmd_status ;;
      13) cmd_list_remote ;;
      14) cmd_list_local ;;
      15) cmd_edit_conf ;;
      0|q|Q) echo "Bye."; exit 0 ;;
      *) echo "Invalid choice." ;;
    esac
    echo
    read -r -p "Press Enter to continue..." _
  done
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [command]

Commands:
  (none)       Interactive menu
  push         Sync local → Nextcloud
  pull         Sync Nextcloud → local
  copy-push    Copy local → Nextcloud (no deletes)
  copy-pull    Copy Nextcloud → local (no deletes)
  dry-push     Dry-run push
  dry-pull     Dry-run pull
  check        Compare local vs remote
  status       Show status
  auto-on      Enable cron auto-sync
  auto-off     Disable cron auto-sync
  auto-run     Run one auto cycle (for cron)
  set-mode M   Set AUTO_MODE to push|pull|bisync
  conf         Show config

Config: $CONF_FILE
EOF
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    "") menu ;;
    push) cmd_push ;;
    pull) cmd_pull ;;
    copy-push) cmd_copy_push ;;
    copy-pull) cmd_copy_pull ;;
    dry-push) cmd_push --dry-run ;;
    dry-pull) cmd_pull --dry-run ;;
    check) cmd_check ;;
    status) cmd_status ;;
    auto-on) cmd_auto_on ;;
    auto-off) cmd_auto_off ;;
    auto-run) cmd_auto_run ;;
    set-mode) cmd_set_auto_mode "${2:-}" ;;
    conf) cmd_edit_conf ;;
    -h|--help|help) usage ;;
    *)
      usage
      die "Unknown command: $cmd"
      ;;
  esac
}

main "$@"
