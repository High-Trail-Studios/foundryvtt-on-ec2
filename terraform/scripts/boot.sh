#!/usr/bin/env bash
#
# Foundry VTT boot script. Fetched from S3 and run on every start by
# foundry-boot.service, which user-data installs (see user-data.sh.tftpl).
#
# Must be idempotent: a fresh instance and a restarted instance both end in the
# same serving state with no manual steps.
#
# Order matters. DNS is updated and verified BEFORE Caddy starts, because Caddy
# requests a certificate the moment it comes up and Let's Encrypt rate-limits
# failed validations at 5 per hostname per hour.

set -euo pipefail

log() { printf '[boot] %s %s\n' "$(date -Is)" "$*"; }
die() { printf '[boot] %s ERROR: %s\n' "$(date -Is)" "$*" >&2; exit 1; }

# shellcheck disable=SC1091
source /etc/foundry.env

MOUNT=/mnt/foundry
CONFIG=/opt/foundry

# ---------------------------------------------------------------------------
# 1. Packages. Idempotent — skipped when already present.
# ---------------------------------------------------------------------------

if ! command -v docker >/dev/null 2>&1; then
  log "installing docker"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends \
    ca-certificates curl gnupg unzip nvme-cli

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo "deb [arch=arm64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update -qq
  apt-get install -y -qq --no-install-recommends \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

# Must survive a reboot, not just first boot. This is the classic miss.
systemctl enable --now docker

# ---------------------------------------------------------------------------
# 2. Data volume. Nitro exposes EBS as NVMe, so resolve the device by matching
#    the volume ID in the NVMe serial rather than trusting /dev/sdf.
# ---------------------------------------------------------------------------

log "locating data volume ${DATA_VOLUME_ID}"
SERIAL="${DATA_VOLUME_ID//-/}"
DEVICE=""

for _ in $(seq 1 30); do
  while read -r name serial; do
    [[ "$serial" == "$SERIAL" ]] && DEVICE="/dev/$name"
  done < <(lsblk -dno NAME,SERIAL)
  [[ -n "$DEVICE" ]] && break
  sleep 2
done

[[ -n "$DEVICE" ]] || die "data volume ${DATA_VOLUME_ID} never appeared"
log "data volume is $DEVICE"

# Format only if there is no filesystem. Never reformat — this holds the
# campaign.
if ! blkid "$DEVICE" >/dev/null 2>&1; then
  log "no filesystem found, creating ext4 (first run)"
  mkfs.ext4 -L foundry "$DEVICE"
fi

mkdir -p "$MOUNT"
if ! mountpoint -q "$MOUNT"; then
  mount "$DEVICE" "$MOUNT"
fi

# nofail: a missing volume must not leave the instance unbootable.
grep -q "LABEL=foundry" /etc/fstab \
  || echo "LABEL=foundry $MOUNT ext4 defaults,nofail 0 2" >> /etc/fstab

mkdir -p "$MOUNT/data" "$MOUNT/caddy/data" "$MOUNT/caddy/config"

# uid 10001 matches the unprivileged user in the image.
chown -R 10001:10001 "$MOUNT/data"

# ---------------------------------------------------------------------------
# 3. DNS. No Elastic IP, so the public address changes on every start.
# ---------------------------------------------------------------------------

TOKEN=$(curl -sf -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
PUBLIC_IP=$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" \
  "http://169.254.169.254/latest/meta-data/public-ipv4")

[[ -n "$PUBLIC_IP" ]] || die "no public IPv4 — the subnet must auto-assign one"
log "public IP is $PUBLIC_IP, updating ${FOUNDRY_DOMAIN}"

CHANGE_ID=$(aws route53 change-resource-record-sets \
  --hosted-zone-id "$ROUTE53_ZONE_ID" \
  --query 'ChangeInfo.Id' --output text \
  --change-batch "$(cat <<JSON
{
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "${FOUNDRY_DOMAIN}",
      "Type": "A",
      "TTL": 60,
      "ResourceRecords": [{"Value": "${PUBLIC_IP}"}]
    }
  }]
}
JSON
)")

log "waiting for Route 53 change $CHANGE_ID to propagate"
aws route53 wait resource-record-sets-changed --id "$CHANGE_ID"

# Route 53 reporting INSYNC is not the same as resolvers returning the new
# value. Confirm before Caddy can burn an ACME failure on a stale record.
log "confirming ${FOUNDRY_DOMAIN} resolves to ${PUBLIC_IP}"
for i in $(seq 1 30); do
  RESOLVED=$(dig +short "$FOUNDRY_DOMAIN" A @1.1.1.1 | tail -1 || true)
  [[ "$RESOLVED" == "$PUBLIC_IP" ]] && break
  [[ $i -eq 30 ]] && die "DNS still resolves to '${RESOLVED:-nothing}', not $PUBLIC_IP — refusing to start Caddy and risk the ACME rate limit"
  sleep 10
done
log "DNS confirmed"

# ---------------------------------------------------------------------------
# 4. Runtime config from S3.
# ---------------------------------------------------------------------------

mkdir -p "$CONFIG"
aws s3 cp "s3://${S3_BUCKET}/config/Dockerfile"         "$CONFIG/Dockerfile" --quiet
aws s3 cp "s3://${S3_BUCKET}/config/docker-compose.yml" "$CONFIG/docker-compose.yml" --quiet
aws s3 cp "s3://${S3_BUCKET}/config/Caddyfile"          "$CONFIG/Caddyfile" --quiet
aws s3 cp "s3://${S3_BUCKET}/config/backup.sh"          /usr/local/bin/foundry-backup.sh --quiet
chmod +x /usr/local/bin/foundry-backup.sh

# ---------------------------------------------------------------------------
# 5. Image: pull if ECR already has this version, otherwise build and push.
#    (REQUIREMENTS.md R13 — the game-night path is always the pull.)
# ---------------------------------------------------------------------------

REGISTRY="${ECR_REPO%%/*}"
IMAGE="${ECR_REPO}:${FOUNDRY_VERSION}"

log "authenticating to ECR"
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

if docker pull "$IMAGE" 2>/dev/null; then
  log "pulled $IMAGE from ECR"
else
  log "$IMAGE not in ECR — building it (first run for this version)"

  ZIP="FoundryVTT-Node-${FOUNDRY_VERSION}.zip"
  BUILD=$(mktemp -d)
  trap 'rm -rf "$BUILD"' EXIT

  aws s3 cp "s3://${S3_BUCKET}/dist/${ZIP}" "$BUILD/$ZIP" --quiet \
    || die "s3://${S3_BUCKET}/dist/${ZIP} not found. Upload the Foundry Node.js package for ${FOUNDRY_VERSION} before starting."

  cp "$CONFIG/Dockerfile" "$BUILD/Dockerfile"

  log "building natively for arm64 — several minutes, once per version"
  docker build \
    --build-arg "FOUNDRY_VERSION=${FOUNDRY_VERSION}" \
    --tag "$IMAGE" \
    "$BUILD"

  log "pushing $IMAGE"
  docker push "$IMAGE"

  rm -rf "$BUILD"
  trap - EXIT
fi

# ---------------------------------------------------------------------------
# 6. Seed from backup if the data volume is empty (migration path).
# ---------------------------------------------------------------------------

if [[ -z "$(ls -A "$MOUNT/data" 2>/dev/null)" ]]; then
  if aws s3 ls "s3://${S3_BUCKET}/backup/" >/dev/null 2>&1 \
     && [[ -n "$(aws s3 ls "s3://${S3_BUCKET}/backup/")" ]]; then
    log "data volume empty and a backup exists — seeding"
    aws s3 sync "s3://${S3_BUCKET}/backup/" "$MOUNT/data/" --quiet
    chown -R 10001:10001 "$MOUNT/data"
  else
    log "data volume empty and no backup — starting fresh"
  fi
fi

# ---------------------------------------------------------------------------
# 7. Backup-on-shutdown, then start.
# ---------------------------------------------------------------------------

cat > /etc/systemd/system/foundry-backup.service <<'UNIT'
[Unit]
Description=Back up Foundry data to S3 on shutdown
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true
ExecStop=/usr/local/bin/foundry-backup.sh
TimeoutStopSec=600

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now foundry-backup.service

cat > "$CONFIG/.env" <<ENV
FOUNDRY_IMAGE=${IMAGE}
FOUNDRY_DOMAIN=${FOUNDRY_DOMAIN}
ACME_EMAIL=${ACME_EMAIL}
FOUNDRY_DATA=${MOUNT}/data
CADDY_DATA=${MOUNT}/caddy/data
CADDY_STATE=${MOUNT}/caddy/config
ENV

log "starting Foundry"
cd "$CONFIG"
docker compose up -d

log "boot complete — https://${FOUNDRY_DOMAIN}"
