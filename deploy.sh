#!/bin/bash
set -e

echo "🚀 Deploying CoreScope to chicagooffline.com..."

NETWORK_NAME="chicagooffline-net"
HEALTH_DIR="$HOME/meshcore-health-check"
HEALTH_ENV="$HEALTH_DIR/.env"

# Stop existing container if running
docker stop corescope 2>/dev/null || true
docker rm corescope 2>/dev/null || true
docker stop meshcore-health-check 2>/dev/null || true
docker rm meshcore-health-check 2>/dev/null || true

# Ensure shared network exists so Caddy can reverse proxy to other containers by name
docker network inspect "$NETWORK_NAME" >/dev/null 2>&1 || docker network create "$NETWORK_NAME"

# Pull latest image
docker pull ghcr.io/kpa-clawbot/corescope:latest

# Ensure meshcore-health-check source exists and is updated
if [ ! -d "$HEALTH_DIR/.git" ]; then
  git clone https://github.com/yellowcooln/meshcore-health-check.git "$HEALTH_DIR"
else
  git -C "$HEALTH_DIR" pull --ff-only origin main
fi

# Create health-check env if missing
if [ ! -f "$HEALTH_ENV" ]; then
  cat > "$HEALTH_ENV" << 'HEALTH_ENV_FILE'
PORT=3090
APP_TITLE=Chicago Mesh Health Check
APP_EYEBROW=Chicago Mesh
APP_HEADLINE=MeshCore Health Check
APP_DESCRIPTION=Generate a test code and measure observer coverage in Chicago.
LOG_LEVEL=info
TRUST_PROXY=1

MQTT_HOST=corescope
MQTT_PORT=1883
MQTT_TOPIC=meshcore/#
MQTT_TRANSPORT=tcp
MQTT_TLS=0

TEST_CHANNEL_NAME=healthcheck
TEST_CHANNEL_SECRET=${TEST_CHANNEL_SECRET:-CHANGE_ME}

SESSION_TTL_SECONDS=900
RESULT_RETENTION_SECONDS=604800
MAX_USES_PER_CODE=3

TURNSTILE_ENABLED=0
HEALTH_ENV_FILE
  echo "⚠️  Created $HEALTH_ENV with a placeholder TEST_CHANNEL_SECRET. Edit this file before using health checks in production."
fi

# If a secret was passed in via env var, write it into the .env (create or update)
if [ -n "${TEST_CHANNEL_SECRET:-}" ] && [ "${TEST_CHANNEL_SECRET}" != "CHANGE_ME" ]; then
  if [ -f "$HEALTH_ENV" ]; then
    sed -i "s|TEST_CHANNEL_SECRET=.*|TEST_CHANNEL_SECRET=${TEST_CHANNEL_SECRET}|" "$HEALTH_ENV"
  fi
fi

# Refuse to deploy with placeholder secret
if grep -q "CHANGE_ME" "$HEALTH_ENV"; then
  echo "❌ TEST_CHANNEL_SECRET is still the placeholder value."
  echo "   Edit $HEALTH_ENV and set a real secret before deploying."
  exit 1
fi

# Build meshcore-health-check image
docker build -t meshcore-health-check:latest "$HEALTH_DIR"

# Create directories if they don't exist
mkdir -p ~/corescope-data ~/caddy-data

# Copy config files
cp config.json ~/corescope-data/config.json
cp Caddyfile ~/Caddyfile

# Start CoreScope
docker run -d --name corescope \
  --restart=unless-stopped \
  -p 80:80 -p 443:443 -p 1883:1883 \
  -v ~/corescope-data:/app/data \
  -v ~/Caddyfile:/etc/caddy/Caddyfile:ro \
  -v ~/caddy-data:/data/caddy \
  --network "$NETWORK_NAME" \
  ghcr.io/kpa-clawbot/corescope:latest

# Start Mesh Health Check behind CoreScope's Caddy
docker run -d --name meshcore-health-check \
  --restart=unless-stopped \
  --env-file "$HEALTH_ENV" \
  -v "$HEALTH_DIR/data:/app/data" \
  --network "$NETWORK_NAME" \
  meshcore-health-check:latest

echo "✅ CoreScope deployed!"
echo "🌐 Web UI: https://chicagooffline.com"
echo "📡 MQTT: mqtt://mqtt.chicagooffline.com:1883"
echo "🩺 Health Check: https://healthcheck.chicagooffline.com"

# Show recent logs (follow only in interactive terminals)
if [ -t 1 ]; then
  docker logs -f corescope
else
  docker logs --tail 20 corescope
fi
