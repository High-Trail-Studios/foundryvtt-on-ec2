#!/usr/bin/env bash
#
# Build the Foundry VTT image LOCALLY, for development and testing.
#
# This is not the deployment path. In production the instance builds its own
# image natively on arm64 and pushes it to ECR (see REQUIREMENTS.md R13), which
# is why Docker is not a prerequisite for adopters.
#
# You supply the Foundry distribution. Sign in to foundryvtt.com with your own
# licensed account, download the "Node.js" package (not "Linux", which is the
# Electron desktop app), and drop the zip in this directory. It is gitignored and must never be committed.
#
#   ./build.sh 14.368                        # build for EC2 (arm64/Graviton)
#   PLATFORM=linux/amd64 ./build.sh 14.368   # build for an x86 host
#
# The default target is arm64 because the EC2 instances this repo provisions
# (t4g.medium / c7g.large) are Graviton. Building on an x86 machine works via
# emulation but is slow — several minutes rather than under one.

set -euo pipefail

FOUNDRY_VERSION="${1:-}"
PLATFORM="${PLATFORM:-linux/arm64}"
IMAGE_NAME="${IMAGE_NAME:-foundryvtt}"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ -n "$FOUNDRY_VERSION" ]] \
  || die "usage: ./build.sh <foundry-version>   e.g. ./build.sh 14.368"

# This release supports v14 only. Refuse rather than build something untested.
[[ "$FOUNDRY_VERSION" == 14.* ]] \
  || die "This release supports Foundry v14 only (got '$FOUNDRY_VERSION')."

cd "$(dirname "$0")"

ZIP="FoundryVTT-Node-${FOUNDRY_VERSION}.zip"
[[ -f "$ZIP" ]] || die "$ZIP not found in $(pwd).
     Download the Node.js package for ${FOUNDRY_VERSION} from
     https://foundryvtt.com using your own licensed account and place it here."

TAG="${IMAGE_NAME}:${FOUNDRY_VERSION}"

printf '==> Building %s for %s\n' "$TAG" "$PLATFORM"

docker buildx build \
  --platform "$PLATFORM" \
  --build-arg "FOUNDRY_VERSION=${FOUNDRY_VERSION}" \
  --tag "$TAG" \
  --load \
  .

printf '==> Built %s\n' "$TAG"
printf '    This image contains licensed Foundry software.\n'
printf '    Push it to a PRIVATE registry only. Never publish it.\n'
