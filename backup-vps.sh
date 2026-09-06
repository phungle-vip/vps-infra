#!/bin/bash
set -euo pipefail

# ===== CONFIG =====
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="${INFRA_DIR:-$SCRIPT_DIR}"
TMP_BASE="/tmp"
DATE=$(date +%F_%H-%M)
TMP_DIR="$TMP_BASE/backup-$DATE"
REMOTE="${REMOTE:-ggdrive:vps-backup/$DATE}"

VOLUMES=(
  vault_data
  kafka-oauth-data
  grafana_data
  elasticsearch_data
  redisinsight_data
)

# ===== START =====
echo "=== Backup started at $(date) ==="

mkdir -p "$TMP_DIR/docker-volumes"

# Helper to find actual docker volume name (with or without compose prefix)
find_volume() {
  local name="$1"
  if docker volume inspect "$name" >/dev/null 2>&1; then
    echo "$name"
  elif docker volume inspect "vps-infra_${name}" >/dev/null 2>&1; then
    echo "vps-infra_${name}"
  else
    echo ""
  fi
}

# 1) Backup Docker volumes -> tar.gz
for V in "${VOLUMES[@]}"; do
  ACTUAL_VOL=$(find_volume "$V")
  if [[ -n "$ACTUAL_VOL" ]]; then
    echo "-> Backing up docker volume: $ACTUAL_VOL (as $V)"
    docker run --rm \
      -v "$ACTUAL_VOL:/data:ro" \
      -v "$TMP_DIR/docker-volumes:/backup" \
      alpine \
      sh -c "tar czf /backup/${V}.tar.gz -C /data ."
  else
    echo "-> [WARNING] Volume $V not found on host, skipping."
  fi
done

# 2) Backup vps-infra (exclude .git + junk + letsencrypt)
echo "-> Uploading vps-infra..."
rclone copy "$INFRA_DIR" "$REMOTE/vps-infra" \
  --exclude ".git/**" \
  --exclude "**/.git/**" \
  --exclude "nginx/letsencrypt/**" \
  --exclude "**/node_modules/**" \
  --exclude "**/target/**" \
  --exclude "**/.cache/**" \
  --progress

# 3) Upload docker volume archives
echo "-> Uploading docker volumes..."
rclone copy "$TMP_DIR/docker-volumes" "$REMOTE/docker-volumes" \
  --filter "+ *.tar.gz" \
  --filter "- *" \
  --progress

# 4) Cleanup
rm -rf "$TMP_DIR"

echo "=== Backup finished at $(date) ==="
echo "Remote location: $REMOTE"
