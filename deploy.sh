#!/bin/bash
set -e

ENVIRONMENT="${ENVIRONMENT:-production}"
echo "🚀 Deploying CoreScope [$ENVIRONMENT]..."

# ── Environment-specific config ──────────────────────────────────────────────
if [ "$ENVIRONMENT" = "dev" ]; then
  SCOPE_VHOST="dev-scope.chicagooffline.com"
  LANDING_VHOST="dev-landing.chicagooffline.com"
  CORESCOPE_CONTAINER="corescope"
  CORESCOPE_IMAGE_MODE="fork"         # build from chicagooffline fork
  CORESCOPE_DATA_DIR="$HOME/corescope-data"
  CORESCOPE_CONFIG="dev-config.json"
  WITH_MQTT=false
  WITH_HEALTH_CHECK=false
  WITH_LANDING=true
  DEV_BANNER=true
else
  SCOPE_VHOST="scope.chicagooffline.com"
  LANDING_VHOST="chicagooffline.com"
  CORESCOPE_CONTAINER="corescope"
  CORESCOPE_IMAGE_MODE="fork"         # both envs run the fork now
  CORESCOPE_DATA_DIR="$HOME/corescope-data"
  CORESCOPE_CONFIG="config.json"
  WITH_MQTT=true
  WITH_HEALTH_CHECK=true
  WITH_LANDING=true
  DEV_BANNER=false
fi

# ── Reset DB ──────────────────────────────────────────────────────────────────
if [ "${RESET_DB:-}" = "true" ]; then
  echo "⚠️  RESET_DB=true — wiping meshcore.db..."
  rm -f "$CORESCOPE_DATA_DIR/meshcore.db"
fi

NETWORK_NAME="chicagooffline-net"
HEALTH_DIR="$HOME/meshcore-health-check"
HEALTH_ENV="$HEALTH_DIR/.env"

# ── Stop all containers this server manages ───────────────────────────────────
docker stop corescope          2>/dev/null || true
docker rm   corescope          2>/dev/null || true
docker stop meshcore-health-check 2>/dev/null || true
docker rm   meshcore-health-check 2>/dev/null || true
docker stop caddy              2>/dev/null || true
docker rm   caddy              2>/dev/null || true

# ── Network ───────────────────────────────────────────────────────────────────
docker network inspect "$NETWORK_NAME" >/dev/null 2>&1 || docker network create "$NETWORK_NAME"

# ── Build CoreScope from chicagooffline fork ──────────────────────────────────
DEV_REPO_DIR="$HOME/CoreScope-chicagooffline"
DEV_BRANCH="deploy/chicagooffline"

echo "📦 Building CoreScope from fork ($DEV_BRANCH)..."
if [ ! -d "$DEV_REPO_DIR/.git" ]; then
  git clone -b "$DEV_BRANCH" https://github.com/emuehlstein/CoreScope-chicagooffline.git "$DEV_REPO_DIR"
else
  git -C "$DEV_REPO_DIR" fetch origin
  git -C "$DEV_REPO_DIR" checkout "$DEV_BRANCH"
  git -C "$DEV_REPO_DIR" reset --hard "origin/$DEV_BRANCH"
fi

DEV_COMMIT=$(git -C "$DEV_REPO_DIR" rev-parse --short HEAD)
DEV_BUILD_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)

docker build -t corescope-chicagooffline:latest \
  --build-arg APP_VERSION="chicagooffline-$ENVIRONMENT" \
  --build-arg GIT_COMMIT="$DEV_COMMIT" \
  --build-arg BUILD_TIME="$DEV_BUILD_TIME" \
  "$DEV_REPO_DIR"

echo "✅ Built corescope-chicagooffline:latest (commit $DEV_COMMIT)"

# ── Directories and config ────────────────────────────────────────────────────
mkdir -p "$CORESCOPE_DATA_DIR" ~/caddy-data ~/landing ~/dev-landing

cp "$CORESCOPE_CONFIG" "$CORESCOPE_DATA_DIR/config.json"
if [ "$ENVIRONMENT" = "dev" ]; then
  cp Caddyfile.dev ~/Caddyfile
else
  cp Caddyfile ~/Caddyfile
fi

if [ "$WITH_LANDING" = true ]; then
  if [ "$DEV_BANNER" = true ]; then
    cp dev-landing/index.html ~/dev-landing/index.html
  else
    cp landing/index.html ~/landing/index.html
  fi
fi

# ── Health check setup (prod only) ───────────────────────────────────────────
if [ "$WITH_HEALTH_CHECK" = true ]; then
  if [ ! -d "$HEALTH_DIR/.git" ]; then
    git clone https://github.com/yellowcooln/meshcore-health-check.git "$HEALTH_DIR"
  else
    git -C "$HEALTH_DIR" fetch origin main
    git -C "$HEALTH_DIR" reset --hard origin/main
  fi

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
  fi

  if [ -n "${TEST_CHANNEL_SECRET:-}" ] && [ "${TEST_CHANNEL_SECRET}" != "CHANGE_ME" ]; then
    sed -i "s|TEST_CHANNEL_SECRET=.*|TEST_CHANNEL_SECRET=${TEST_CHANNEL_SECRET}|" "$HEALTH_ENV"
  fi

  if grep -q "CHANGE_ME" "$HEALTH_ENV"; then
    echo "❌ TEST_CHANNEL_SECRET is still the placeholder value."
    echo "   Edit $HEALTH_ENV and set a real secret before deploying."
    exit 1
  fi

  docker build -t meshcore-health-check:latest "$HEALTH_DIR"
fi

# ── Start CoreScope ───────────────────────────────────────────────────────────
MQTT_PORTS=""
if [ "$WITH_MQTT" = true ]; then
  MQTT_PORTS="-p 1883:1883"
fi

docker rm -f "$CORESCOPE_CONTAINER" 2>/dev/null || true
docker run -d --name "$CORESCOPE_CONTAINER" \
  --restart=unless-stopped \
  $MQTT_PORTS \
  -e DISABLE_CADDY=true \
  -e DISABLE_MOSQUITTO=$([ "$WITH_MQTT" = true ] && echo false || echo true) \
  -v "$CORESCOPE_DATA_DIR:/app/data" \
  --network "$NETWORK_NAME" \
  corescope-chicagooffline:latest

# ── Start Caddy ───────────────────────────────────────────────────────────────
CADDY_LANDING_MOUNTS=""
if [ "$DEV_BANNER" = true ]; then
  CADDY_LANDING_MOUNTS="-v ~/dev-landing:/srv/dev-landing:ro"
else
  CADDY_LANDING_MOUNTS="-v ~/landing:/srv/landing:ro -v ~/dev-landing:/srv/dev-landing:ro"
fi

docker rm -f caddy 2>/dev/null || true
docker run -d --name caddy \
  --restart=unless-stopped \
  -p 80:80 -p 443:443 \
  -v ~/Caddyfile:/etc/caddy/Caddyfile:ro \
  -v ~/caddy-data:/data/caddy \
  $CADDY_LANDING_MOUNTS \
  --network "$NETWORK_NAME" \
  caddy:latest

# ── Start Health Check (prod only) ───────────────────────────────────────────
if [ "$WITH_HEALTH_CHECK" = true ]; then
  docker rm -f meshcore-health-check 2>/dev/null || true
  docker run -d --name meshcore-health-check \
    --restart=unless-stopped \
    --env-file "$HEALTH_ENV" \
    -v "$HEALTH_DIR/data:/app/data" \
    --network "$NETWORK_NAME" \
    meshcore-health-check:latest
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "✅ CoreScope [$ENVIRONMENT] deployed!"
if [ "$ENVIRONMENT" = "dev" ]; then
  echo "🔧 Scope:  https://dev-scope.chicagooffline.com"
  echo "🔧 Landing: https://dev-landing.chicagooffline.com"
else
  echo "🌐 Landing: https://chicagooffline.com"
  echo "📡 Scope:   https://scope.chicagooffline.com"
  echo "📻 MQTT:    mqtt://mqtt.chicagooffline.com:1883"
  echo "🩺 Health:  https://health.chicagooffline.com"
fi

if [ -t 1 ]; then
  docker logs -f corescope
else
  docker logs --tail 20 corescope
fi
