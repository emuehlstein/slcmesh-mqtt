#!/bin/bash
set -e

ENVIRONMENT="${ENVIRONMENT:-production}"
echo "🚀 Deploying [$ENVIRONMENT] via docker compose..."

# ── Bootstrap Docker + Compose if missing ────────────────────────────────────
if ! command -v docker &>/dev/null; then
  echo "📦 Docker not found — installing..."
  sudo cloud-init status --wait 2>/dev/null || sleep 30
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER"
  echo "⚠️  Docker installed. Log out and back in, then re-run."
  exit 1
fi

# ── Select compose file ──────────────────────────────────────────────────────
if [ "$ENVIRONMENT" = "dev" ]; then
  COMPOSE_FILE="docker-compose.dev.yml"
  CONFIG_SRC="dev-config.json"
else
  COMPOSE_FILE="docker-compose.prod.yml"
  CONFIG_SRC="config.json"
fi

# ── Clone/update third-party repos ──────────────────────────────────────────
clone_or_pull() {
  local url="$1" dir="$2" branch="${3:-main}"
  if [ ! -d "$dir/.git" ]; then
    git clone ${branch:+-b "$branch"} "$url" "$dir"
  else
    git -C "$dir" fetch origin
    git -C "$dir" reset --hard "origin/$branch"
  fi
}

FORK_DIR="./CoreScope-chicagooffline"
clone_or_pull "https://github.com/emuehlstein/CoreScope-chicagooffline.git" "$FORK_DIR" "deploy/chicagooffline"
clone_or_pull "https://github.com/yellowcooln/meshcore-health-check.git" "./meshcore-health-check" "main"
clone_or_pull "https://github.com/yellowcooln/meshcore-mqtt-live-map.git" "./meshcore-mqtt-live-map" "main"
clone_or_pull "https://github.com/agessaman/meshcore-web-keygen.git" "./meshcore-web-keygen" "main"

# ── Resolve config (inject secrets) ──────────────────────────────────────────
cp "$CONFIG_SRC" config.resolved.json
[ -n "${BROKER_CORESCOPE_PASSWORD:-}" ] && sed -i "s/BROKER_CORESCOPE_PASSWORD/${BROKER_CORESCOPE_PASSWORD}/g" config.resolved.json
[ -n "${CHIMESH_VIEWER_PASSWORD:-}" ]   && sed -i "s/CHIMESH_VIEWER_PASSWORD/${CHIMESH_VIEWER_PASSWORD}/g" config.resolved.json

# ── Generate per-service env files ───────────────────────────────────────────
if [ "$ENVIRONMENT" = "dev" ]; then
  BROKER_AUDIENCE="wsmqtt-dev.chicagooffline.com"
  LIVEMAP_MQTT="corescope-dev"
  LIVEMAP_SCOPE="https://dev-scope.chicagooffline.com"
  HEALTH_TITLE="Chicago Mesh Health Check [dev]"
  HEALTH_PORT=3091
  HEALTH_MQTT="mosquitto"
else
  BROKER_AUDIENCE="wsmqtt.chicagooffline.com"
  LIVEMAP_MQTT="mosquitto"
  LIVEMAP_SCOPE="https://scope.chicagooffline.com"
  HEALTH_TITLE="Chicago Mesh Health Check"
  HEALTH_PORT=3090
  HEALTH_MQTT="mosquitto"
fi

cat > .env.broker << EOF
MQTT_WS_PORT=8883
MQTT_HOST=0.0.0.0
AUTH_EXPECTED_AUDIENCE=$BROKER_AUDIENCE
SUBSCRIBER_MAX_CONNECTIONS_DEFAULT=2
SUBSCRIBER_1=corescope:${BROKER_CORESCOPE_PASSWORD:-changeme}:2
SUBSCRIBER_2=admin:${BROKER_ADMIN_PASSWORD:-changeme}:1:5
ABUSE_ENFORCEMENT_ENABLED=false
EOF

cat > .env.healthcheck << EOF
PORT=$HEALTH_PORT
APP_TITLE=$HEALTH_TITLE
APP_EYEBROW=Chicago Mesh
APP_HEADLINE=MeshCore Health Check
APP_DESCRIPTION=Generate a test code and measure observer coverage in Chicago.
LOG_LEVEL=info
TRUST_PROXY=1
MQTT_HOST=$HEALTH_MQTT
MQTT_PORT=1883
MQTT_TOPIC=meshcore/#
MQTT_TRANSPORT=tcp
MQTT_TLS=0
TEST_CHANNEL_NAME=healthcheck
TEST_CHANNEL_SECRET=${TEST_CHANNEL_SECRET:-changeme}
SESSION_TTL_SECONDS=900
RESULT_RETENTION_SECONDS=604800
MAX_USES_PER_CODE=3
TURNSTILE_ENABLED=0
OBSERVERS_FILE=data/observer.json
EOF

cat > .env.livemap << EOF
SITE_TITLE=Chicago Mesh Live Map
SITE_DESCRIPTION=Live view of Chicago MeshCore nodes, message routes, and advert paths.
SITE_FEED_NOTE=Feed: chicagooffline.com MQTT.
MQTT_HOST=$LIVEMAP_MQTT
MQTT_PORT=1883
MQTT_USERNAME=
MQTT_PASSWORD=
MQTT_TRANSPORT=tcp
MQTT_TLS=false
MQTT_TOPIC=meshcore/#
MAP_START_LAT=41.8781
MAP_START_LON=-87.6298
MAP_START_ZOOM=10
DISTANCE_UNITS=mi
PACKET_ANALYZER_URL=$LIVEMAP_SCOPE
EOF

# ── Reset DB if requested ────────────────────────────────────────────────────
if [ "${RESET_DB:-}" = "true" ]; then
  echo "⚠️  RESET_DB=true — wiping database..."
  docker compose -f "$COMPOSE_FILE" down -v --remove-orphans 2>/dev/null || true
fi

# ── Deploy ───────────────────────────────────────────────────────────────────
export CORESCOPE_FORK_DIR="$FORK_DIR"
export HEALTH_CHECK_DIR="./meshcore-health-check"
export LIVEMAP_DIR="./meshcore-mqtt-live-map"
export KEYGEN_DIR="./meshcore-web-keygen"

docker compose -f "$COMPOSE_FILE" build --no-cache
docker compose -f "$COMPOSE_FILE" up -d --remove-orphans

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "✅ Deployed [$ENVIRONMENT]!"
if [ "$ENVIRONMENT" = "dev" ]; then
  echo "🔧 Scope:   https://dev-scope.chicagooffline.com"
  echo "🔧 Landing: https://dev-landing.chicagooffline.com"
  echo "🩺 Health:  https://dev-health.chicagooffline.com"
  echo "🔑 Keygen:  https://dev-keygen.chicagooffline.com"
  echo "🗺️  LiveMap: https://dev-livemap.chicagooffline.com"
else
  echo "🌐 Landing: https://chicagooffline.com"
  echo "📡 Scope:   https://scope.chicagooffline.com"
  echo "📻 MQTT:    mqtt://mqtt.chicagooffline.com:1883"
  echo "🩺 Health:  https://health.chicagooffline.com"
  echo "🔑 Keygen:  https://keygen.chicagooffline.com"
  echo "🗺️  LiveMap: https://livemap.chicagooffline.com"
fi

# ── Smoke test ───────────────────────────────────────────────────────────────
echo ""
echo "🔍 Running smoke tests..."
sleep 5  # give containers a moment to start

FAIL=0
for svc in $(docker compose -f "$COMPOSE_FILE" ps --services); do
  STATUS=$(docker compose -f "$COMPOSE_FILE" ps --format json "$svc" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('State','unknown'))" 2>/dev/null || echo "unknown")
  if [ "$STATUS" = "running" ]; then
    echo "  ✅ $svc"
  else
    echo "  ❌ $svc ($STATUS)"
    FAIL=1
  fi
done

if [ "$FAIL" = "1" ]; then
  echo ""
  echo "⚠️  Some services failed to start. Check logs with:"
  echo "   docker compose -f $COMPOSE_FILE logs <service>"
  exit 1
fi

echo ""
echo "🎉 All services running."
