# syntax=docker/dockerfile:1
#
# Foundry VTT container image — v14 only.
#
# This image does NOT ship Foundry VTT. You supply your own licensed copy at
# build time: sign in to foundryvtt.com with your own account, download the
# "Linux/NodeJS" package, and place the zip beside this Dockerfile.
#
# The image you build DOES contain licensed software. Keep it in a private
# registry (ECR). Never push it anywhere public.
#
#   ./build.sh 14.364

ARG UBUNTU_VERSION=26.04

# ---------------------------------------------------------------------------
# extract — unpack the distribution here so the 250MB zip never lands in a
# layer of the final image. Deleting it in a later RUN does not reclaim the
# space; only keeping it out of the runtime stage does.
# ---------------------------------------------------------------------------
FROM ubuntu:${UBUNTU_VERSION} AS extract

ARG FOUNDRY_VERSION

RUN apt-get update \
 && apt-get install -y --no-install-recommends unzip \
 && rm -rf /var/lib/apt/lists/*

COPY FoundryVTT-Linux-${FOUNDRY_VERSION}.zip /tmp/foundry.zip
RUN unzip -q /tmp/foundry.zip -d /opt/foundryvtt \
 && rm /tmp/foundry.zip

# ---------------------------------------------------------------------------
# runtime
# ---------------------------------------------------------------------------
FROM ubuntu:${UBUNTU_VERSION}

ARG FOUNDRY_VERSION
ARG NODE_MAJOR=24

LABEL org.opencontainers.image.title="foundryvtt" \
      org.opencontainers.image.version="${FOUNDRY_VERSION}" \
      org.opencontainers.image.vendor="High Tail Studios" \
      org.opencontainers.image.description="Foundry VTT runtime. Contains licensed software — do not publish."

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
 && curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash - \
 && apt-get install -y --no-install-recommends nodejs \
 && apt-get purge -y --auto-remove curl gnupg \
 && rm -rf /var/lib/apt/lists/*

# Run unprivileged. Foundry needs no root, and this port faces the internet.
# UID is fixed so the host can chown the EBS data directory to match.
RUN useradd --system --create-home --uid 10001 --shell /usr/sbin/nologin foundry \
 && mkdir -p /data \
 && chown foundry:foundry /data

COPY --from=extract --chown=foundry:foundry /opt/foundryvtt /opt/foundryvtt

USER foundry
WORKDIR /opt/foundryvtt

# Worlds (LevelDB), assets, and config all live here. Mounted from the
# persistent EBS volume at runtime — never baked into the image.
VOLUME ["/data"]
EXPOSE 30000

# Any non-error response means the server is up and answering. Deliberately
# not pinned to a specific route so a Foundry routing change can't send the
# container into a restart loop.
HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=3 \
  CMD node -e "require('http').get('http://127.0.0.1:30000/',r=>process.exit(r.statusCode<400?0:1)).on('error',()=>process.exit(1))"

ENTRYPOINT ["node", "resources/app/main.js"]
CMD ["--dataPath=/data"]
