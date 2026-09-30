#!/usr/bin/env bash
#
# Park the hostname on shutdown. Run by systemd (foundry-dns.service) on stop.
#
# Without this, between sessions the A record keeps pointing at a public IP
# this instance has released. AWS reassigns those, so whoever holds it next
# would receive your players' traffic — and, because DNS points at them, could
# pass Let's Encrypt's HTTP challenge for your hostname.
#
# Parked, not deleted: a deleted name gets negatively cached by resolvers (up to
# 15 minutes with Route 53's default SOA), which would outlast the boot
# script's DNS check on the next start. 192.0.2.1 is TEST-NET-1 (RFC 5737),
# reserved for documentation and never assigned to anyone.
#
# Conditional, and atomic: Route 53 applies a change batch all-or-nothing, and a
# DELETE must match the existing record exactly. DELETE-our-IP + CREATE-parked
# therefore swaps the record only if it still points at this instance. If
# someone has pointed the hostname elsewhere, the batch fails and nothing
# changes.
#
# Never fails the shutdown. A record left stale is the pre-existing behaviour,
# not a reason to hang a stop.

set -uo pipefail

log() { printf '[dns-park] %s %s\n' "$(date -Is)" "$*"; }

# shellcheck disable=SC1091
source /etc/foundry.env

PARKED_IP=192.0.2.1

TOKEN=$(curl -sf -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
PUBLIC_IP=$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" \
  "http://169.254.169.254/latest/meta-data/public-ipv4")

if [[ -z "$PUBLIC_IP" ]]; then
  log "no public IP known; leaving the record alone"
  exit 0
fi

log "parking ${FOUNDRY_DOMAIN}: ${PUBLIC_IP} -> ${PARKED_IP}"

if OUT=$(aws route53 change-resource-record-sets \
  --hosted-zone-id "$ROUTE53_ZONE_ID" \
  --query 'ChangeInfo.Id' --output text \
  --change-batch "$(cat <<JSON
{
  "Comment": "foundry: park on shutdown",
  "Changes": [
    {
      "Action": "DELETE",
      "ResourceRecordSet": {
        "Name": "${FOUNDRY_DOMAIN}",
        "Type": "A",
        "TTL": ${DNS_TTL},
        "ResourceRecords": [{"Value": "${PUBLIC_IP}"}]
      }
    },
    {
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "${FOUNDRY_DOMAIN}",
        "Type": "A",
        "TTL": ${DNS_TTL},
        "ResourceRecords": [{"Value": "${PARKED_IP}"}]
      }
    }
  ]
}
JSON
)" 2>&1); then
  log "parked ($OUT)"
else
  # Most likely the record no longer points at this instance, which is exactly
  # the case where we must not touch it.
  log "not parked, record left unchanged: $OUT"
fi

exit 0
