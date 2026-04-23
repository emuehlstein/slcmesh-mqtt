#!/bin/bash
set -e

ENVIRONMENT="${ENVIRONMENT:-production}"
echo "🚀 Deploying CoreScope [$ENVIRONMENT]..."

# ── Bootstrap Docker if not installed ────────────────────────────────────────
if ! command -v docker &>/dev/null; then
  echo "📦 Docker not found — installing..."
  # Wait for cloud-init to finish (clears apt locks on fresh instances)
  sudo cloud-init status --wait 2>/dev/null || sleep 30
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER"
  echo "⚠️  Docker installed but group membership requires logout. Retry deploy or use 'sudo docker' manually."
  exit 1
fi

# ── Environment-specific config ──────────────────────────────────────────────
if [ "$ENVIRONMENT" = "dev" ]; then
  SCOPE_VHOST="dev-scope.chicagooffline.com"
  LANDING_VHOST="dev-landing.chicagooffline.com"
  CORESCOPE_CONTAINER="corescope-dev"
  CORESCOPE_IMAGE_MODE="fork"         # build from chicagooffline fork
  CORESCOPE_DATA_DIR="$HOME/corescope-dev-data"
  CORESCOPE_CONFIG="dev-config.json"
  WITH_MQTT=true              # standalone Mosquitto container (same as prod)
  WITH_WSMQTT_BROKER=true       # deploy standalone WS broker
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
  WITH_MQTT=true              # Run standalone Mosquitto container
  WITH_WSMQTT_BROKER=true        # Run WS broker (meshcore-mqtt-broker)
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

# ── Stop containers for THIS environment ──────────────────────────────────────
docker stop "$CORESCOPE_CONTAINER" 2>/dev/null || true
docker rm   "$CORESCOPE_CONTAINER" 2>/dev/null || true
if [ "$WITH_HEALTH_CHECK" = true ]; then
  docker stop meshcore-health-check 2>/dev/null || true
  docker rm   meshcore-health-check 2>/dev/null || true
fi
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

docker build --no-cache -t corescope-chicagooffline:latest \
  --build-arg APP_VERSION="chicagooffline-$ENVIRONMENT" \
  --build-arg GIT_COMMIT="$DEV_COMMIT" \
  --build-arg BUILD_TIME="$DEV_BUILD_TIME" \
  "$DEV_REPO_DIR"

echo "✅ Built corescope-chicagooffline:latest (commit $DEV_COMMIT)"

# ── Directories and config ────────────────────────────────────────────────────
mkdir -p "$CORESCOPE_DATA_DIR" ~/caddy-data ~/landing ~/dev-landing

# Inject broker password into config before copying (both environments use WS broker now)
if [ -n "${BROKER_CORESCOPE_PASSWORD:-}" ]; then
  sed "s/BROKER_CORESCOPE_PASSWORD/${BROKER_CORESCOPE_PASSWORD}/g" "$CORESCOPE_CONFIG" > /tmp/corescope-config-resolved.json
  cp /tmp/corescope-config-resolved.json "$CORESCOPE_DATA_DIR/config.json"
else
  cp "$CORESCOPE_CONFIG" "$CORESCOPE_DATA_DIR/config.json"
fi
if [ "$ENVIRONMENT" = "dev" ]; then
  cp Caddyfile.dev ~/Caddyfile
else
  cp Caddyfile ~/Caddyfile
fi

if [ "$WITH_LANDING" = true ]; then
  if [ "$DEV_BANNER" = true ]; then
    cp dev-landing/index.html ~/dev-landing/index.html
    cp dev-landing/contributors.html ~/dev-landing/contributors.html
  else
    cp landing/index.html ~/landing/index.html
    cp landing/contributors.html ~/landing/contributors.html
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

# Persist observer coordinates across container restarts
# Default path is /app/observer.json (not in the mounted volume) — this moves it to /app/data/
OBSERVERS_FILE=data/observer.json
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

# ── Start WS MQTT Broker ──────────────────────────────────────────────────────
if [ "${WITH_WSMQTT_BROKER:-false}" = true ]; then
  BROKER_DIR="$(pwd)/meshcore-mqtt-broker"
  BROKER_ENV="$HOME/meshcore-mqtt-broker.env"
  BROKER_DATA="$HOME/meshcore-mqtt-broker-data"
  mkdir -p "$BROKER_DATA"

  # Dynamic audience based on environment
  if [ "$ENVIRONMENT" = "dev" ]; then
    BROKER_AUDIENCE="wsmqtt-dev.chicagooffline.com"
  else
    BROKER_AUDIENCE="wsmqtt.chicagooffline.com"
  fi

  echo "📝 Writing $BROKER_ENV (audience: $BROKER_AUDIENCE)..."
  cat > "$BROKER_ENV" << BROKER_ENV_FILE
MQTT_WS_PORT=8883
MQTT_HOST=0.0.0.0
AUTH_EXPECTED_AUDIENCE=$BROKER_AUDIENCE
SUBSCRIBER_MAX_CONNECTIONS_DEFAULT=2
SUBSCRIBER_1=corescope:${BROKER_CORESCOPE_PASSWORD}:2
SUBSCRIBER_2=admin:${BROKER_ADMIN_PASSWORD:-changeme}:1:5
ABUSE_ENFORCEMENT_ENABLED=false
ABUSE_PERSISTENCE_PATH=/data/abuse-detection.db
ABUSE_DUPLICATE_WINDOW_SIZE=100
ABUSE_DUPLICATE_WINDOW_MS=300000
ABUSE_DUPLICATE_THRESHOLD=10
ABUSE_MAX_DUPLICATES_PER_PACKET=5
ABUSE_DUPLICATE_RATE_THRESHOLD=0.3
ABUSE_DUPLICATE_RATE_WINDOW_MS=300000
ABUSE_BUCKET_CAPACITY=20
ABUSE_BUCKET_REFILL_RATE=3
ABUSE_MAX_PACKET_SIZE=255
ABUSE_MAX_TOPICS_PER_DAY=3
ABUSE_ANOMALY_THRESHOLD=10
ABUSE_MAX_IATA_CHANGES_24H=3
ABUSE_TOPIC_HISTORY_SIZE=50
ABUSE_TOPIC_HISTORY_WINDOW_MS=86400000
ABUSE_PERSISTENCE_INTERVAL_MS=300000
BROKER_ENV_FILE

  # Build if image doesn't exist
  if ! docker image inspect meshcore-mqtt-broker:latest >/dev/null 2>&1; then
    docker build --no-cache -t meshcore-mqtt-broker:latest "$BROKER_DIR"
  fi

  # Only create broker container if not already running (survives app deploys)
  if docker inspect meshcore-mqtt-broker &>/dev/null && [ "$(docker inspect -f '{{.State.Running}}' meshcore-mqtt-broker)" = "true" ]; then
    echo "✅ meshcore-mqtt-broker already running (not restarting)"
  else
    echo "🔐 Starting meshcore-mqtt-broker..."
    docker rm -f meshcore-mqtt-broker 2>/dev/null || true
    docker run -d \
      --name meshcore-mqtt-broker \
      --restart=unless-stopped \
      --env-file "$BROKER_ENV" \
      -v "$BROKER_DATA:/data" \
      --network "$NETWORK_NAME" \
      meshcore-mqtt-broker:latest
    echo "✅ meshcore-mqtt-broker running"
  fi
fi

# ── Start Mosquitto (standalone) ────────────────────────────────────────────────
if [ "$WITH_MQTT" = true ]; then
  # Only create Mosquitto container if not already running (survives app deploys)
  if docker inspect mosquitto &>/dev/null && [ "$(docker inspect -f '{{.State.Running}}' mosquitto)" = "true" ]; then
    echo "✅ Mosquitto already running (not restarting)"
  else
    echo "📡 Starting standalone Mosquitto..."
    mkdir -p ~/mosquitto-data
    docker rm -f mosquitto 2>/dev/null || true
    docker run -d --name mosquitto \
      --restart=unless-stopped \
      -p 1883:1883 \
      -v ~/mosquitto-data:/mosquitto/data \
      -v ~/chimesh-mqtt/mosquitto/mosquitto.conf:/mosquitto/config/mosquitto.conf:ro \
      --network "$NETWORK_NAME" \
      eclipse-mosquitto:2
    echo "✅ Mosquitto running on port 1883"
  fi
fi

# ── Start CoreScope ───────────────────────────────────────────────────────────
docker rm -f "$CORESCOPE_CONTAINER" 2>/dev/null || true
docker run -d --name "$CORESCOPE_CONTAINER" \
  --restart=unless-stopped \
  -e DISABLE_CADDY=true \
  -e DISABLE_MOSQUITTO=true \
  -v "$CORESCOPE_DATA_DIR:/app/data" \
  --network "$NETWORK_NAME" \
  corescope-chicagooffline:latest

# ── Start Caddy ───────────────────────────────────────────────────────────────
CADDY_LANDING_MOUNTS=""
if [ "$DEV_BANNER" = true ]; then
  CADDY_LANDING_MOUNTS="-v $HOME/dev-landing:/srv/dev-landing:ro"
else
  CADDY_LANDING_MOUNTS="-v $HOME/landing:/srv/landing:ro -v $HOME/dev-landing:/srv/dev-landing:ro"
fi

docker rm -f caddy 2>/dev/null || true
docker run -d --name caddy \
  --restart=unless-stopped \
  -p 80:80 -p 443:443 \
  -v $HOME/Caddyfile:/etc/caddy/Caddyfile:ro \
  -v $HOME/caddy-data:/data/caddy \
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
  docker logs -f "$CORESCOPE_CONTAINER"
else
  docker logs --tail 20 "$CORESCOPE_CONTAINER"
fi
