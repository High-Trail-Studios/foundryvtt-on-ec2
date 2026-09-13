#!/usr/bin/env bash
#
# Back up Foundry data to S3. Run by systemd on shutdown.
#
# CRITICAL: Foundry v14 stores worlds in LevelDB. Copying an open LevelDB
# yields a torn snapshot — a MANIFEST referencing SST files that compaction
# has already removed. It looks fine and fails at restore. So Foundry is
# stopped first, every time, without exception.

set -euo pipefail

log() { printf '[backup] %s %s\n' "$(date -Is)" "$*"; }

# shellcheck disable=SC1091
source /etc/foundry.env

MOUNT=/mnt/foundry
CONFIG=/opt/foundry

if [[ ! -d "$MOUNT/data" ]]; then
  log "no data directory, nothing to back up"
  exit 0
fi

# Stop Foundry before copying anything. This is the whole point.
if [[ -f "$CONFIG/docker-compose.yml" ]]; then
  log "stopping Foundry so the world database is consistent"
  cd "$CONFIG"
  docker compose down --timeout 60 || log "compose down failed; continuing"
fi

log "syncing to s3://${S3_BUCKET}/backup/"
aws s3 sync "$MOUNT/data/" "s3://${S3_BUCKET}/backup/" --delete --quiet

log "backup complete"
