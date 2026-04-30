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
clone_or_pull "https://github.com/emuehlstein/meshcore-health-check.git" "./meshcore-health-check" "main"
clone_or_pull "https://github.com/yellowcooln/meshcore-mqtt-live-map.git" "./meshcore-mqtt-live-map" "main"
# Keygen is now bundled in ./keygen/ (themed for Chicago Offline)

# ── Resolve config (inject secrets) ──────────────────────────────────────────
cp "$CONFIG_SRC" config.resolved.json
[ -n "${BROKER_CORESCOPE_PASSWORD:-}" ] && sed -i "s/BROKER_CORESCOPE_PASSWORD/${BROKER_CORESCOPE_PASSWORD}/g" config.resolved.json
[ -n "${CHIMESH_VIEWER_PASSWORD:-}" ]   && sed -i "s/CHIMESH_VIEWER_PASSWORD/${CHIMESH_VIEWER_PASSWORD}/g" config.resolved.json

# ── Generate per-service env files ───────────────────────────────────────────
if [ "$ENVIRONMENT" = "dev" ]; then
  BROKER_AUDIENCE="wsmqtt-dev.chicagooffline.com"
  LIVEMAP_MQTT="mosquitto"
  LIVEMAP_SCOPE="https://dev-scope.chicagooffline.com"
  HEALTH_TITLE="Chicago Mesh Health Check [dev]"
  HEALTH_PORT=3090
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
SUBSCRIBER_MAX_CONNECTIONS_DEFAULT=4
SUBSCRIBER_1=corescope:${BROKER_CORESCOPE_PASSWORD:-changeme}:4
SUBSCRIBER_2=admin:${BROKER_ADMIN_PASSWORD:-changeme}:2:5
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

# Observer Matrix MQTT sources — connects to ALL environments (dev + prod + CM)
# Local WS broker is internal (ws://), remote is external (wss://)
LOCAL_PW="${BROKER_CORESCOPE_PASSWORD:-changeme}"
REMOTE_PW="${BROKER_REMOTE_CORESCOPE_PASSWORD:-$LOCAL_PW}"
VIEWER_PW="${CHIMESH_VIEWER_PASSWORD:-changeme}"

# Only brokers where we have wildcard read access (viewer/corescope/no-auth).
# JWT-only brokers (LetsMesh US/EU, rflab) restrict reads to per-key topics —
# our observer-matrix key gets zero messages on meshcore/#. Add them back
# when/if we obtain viewer credentials.
if [ "$ENVIRONMENT" = "dev" ]; then
  # Running on dev: CO-DEV local (internal ws), CO = prod (external wss)
  MQTT_SOURCES_JSON='[{"name":"chimesh","label":"CM","broker":"wss://mqtt.chimesh.org:443","auth":"userpass","username":"viewer","password":"'"$VIEWER_PW"'","topics":["meshcore/#"]},{"name":"co","label":"CO","broker":"wss://wsmqtt.chicagooffline.com:443","auth":"userpass","username":"corescope","password":"'"$REMOTE_PW"'","topics":["meshcore/#"]},{"name":"co-dev","label":"CO-DEV","broker":"ws://meshcore-mqtt-broker:8883","auth":"userpass","username":"corescope","password":"'"$LOCAL_PW"'","topics":["meshcore/#"]},{"name":"co-tcp","label":"CO-TCP","broker":"mqtt://mqtt.chioff.com:1883","auth":"none","topics":["meshcore/#"]}]'
else
  # Running on prod: CO local (internal ws), CO-DEV = dev (external wss)
  MQTT_SOURCES_JSON='[{"name":"chimesh","label":"CM","broker":"wss://mqtt.chimesh.org:443","auth":"userpass","username":"viewer","password":"'"$VIEWER_PW"'","topics":["meshcore/#"]},{"name":"co","label":"CO","broker":"ws://meshcore-mqtt-broker:8883","auth":"userpass","username":"corescope","password":"'"$LOCAL_PW"'","topics":["meshcore/#"]},{"name":"co-dev","label":"CO-DEV","broker":"wss://wsmqtt-dev.chicagooffline.com:443","auth":"userpass","username":"corescope","password":"'"$REMOTE_PW"'","topics":["meshcore/#"]},{"name":"co-tcp","label":"CO-TCP","broker":"mqtt://mqtt.chioff.com:1883","auth":"none","topics":["meshcore/#"]}]'
fi

# Preserve existing Ed25519 keypair if present (identity persists across deploys)
OM_PRIV=""
OM_PUB=""
if [ -f .env.observer-matrix ]; then
  OM_PRIV=$(grep '^ED25519_PRIVATE_KEY_HEX=' .env.observer-matrix 2>/dev/null | cut -d= -f2 || true)
  OM_PUB=$(grep '^ED25519_PUBLIC_KEY_HEX=' .env.observer-matrix 2>/dev/null | cut -d= -f2 || true)
fi

cat > .env.observer-matrix << EOF
PORT=3100
STALE_THRESHOLD_MS=900000
MQTT_SOURCES=$MQTT_SOURCES_JSON
EOF

# Append persisted keypair (if empty, server auto-generates and logs keys)
if [ -n "$OM_PRIV" ] && [ -n "$OM_PUB" ]; then
  echo "ED25519_PRIVATE_KEY_HEX=$OM_PRIV" >> .env.observer-matrix
  echo "ED25519_PUBLIC_KEY_HEX=$OM_PUB" >> .env.observer-matrix
fi

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

# ── Migrate from deploy.sh host dirs → compose volumes (one-time) ───────────
# Old deploy.sh used bind mounts in ~/. On first compose deploy, seed named
# volumes from those directories so we keep Caddy certs, CoreScope DB, etc.
migrate_dir_to_volume() {
  local host_dir="$1" vol_name="$2"
  [ -d "$host_dir" ] || return 0
  # Check if the volume already has data (container was run before)
  local has_data
  has_data=$(docker run --rm -v "${vol_name}:/vol" alpine sh -c 'ls -A /vol 2>/dev/null | head -1')
  if [ -z "$has_data" ]; then
    echo "📦 Migrating $host_dir → volume $vol_name..."
    docker run --rm \
      -v "${host_dir}:/src:ro" \
      -v "${vol_name}:/dst" \
      alpine sh -c 'cp -a /src/. /dst/'
    echo "  ✅ Done"
  fi
}

PROJECT="chimesh-mqtt"  # compose project name (directory name)
if [ "$ENVIRONMENT" = "dev" ]; then
  migrate_dir_to_volume "$HOME/corescope-dev-data"   "${PROJECT}_corescope-dev-data"
  migrate_dir_to_volume "$HOME/caddy-data"           "${PROJECT}_caddy-data"
else
  migrate_dir_to_volume "$HOME/corescope-data"       "${PROJECT}_corescope-data"
  migrate_dir_to_volume "$HOME/caddy-data"           "${PROJECT}_caddy-data"
fi
migrate_dir_to_volume "$HOME/mosquitto-data"         "${PROJECT}_mosquitto-data"
migrate_dir_to_volume "$HOME/meshcore-mqtt-broker-data" "${PROJECT}_broker-data"

# Health check data
if [ "$ENVIRONMENT" = "dev" ]; then
  [ -d "$HOME/meshcore-health-check-dev/data" ] && \
    migrate_dir_to_volume "$HOME/meshcore-health-check-dev/data" "${PROJECT}_healthcheck-data"
else
  [ -d "$HOME/meshcore-health-check/data" ] && \
    migrate_dir_to_volume "$HOME/meshcore-health-check/data" "${PROJECT}_healthcheck-data"
fi

# ── Stop old deploy.sh containers + network (one-time cleanup) ─────────────
# If legacy standalone containers exist, stop them so compose can take over.
for c in corescope corescope-dev caddy mosquitto meshcore-mqtt-broker meshcore-health-check meshcore-health-check-dev meshmap-live; do
  if docker inspect "$c" &>/dev/null 2>&1; then
    echo "🧹 Stopping legacy container: $c"
    docker stop "$c" 2>/dev/null || true
    docker rm   "$c" 2>/dev/null || true
  fi
done

# Remove old manually-created network so compose can recreate with proper labels
if docker network inspect chicagooffline-net &>/dev/null 2>&1; then
  LABEL=$(docker network inspect chicagooffline-net --format '{{index .Labels "com.docker.compose.network"}}' 2>/dev/null || true)
  if [ -z "$LABEL" ]; then
    echo "🧹 Removing legacy chicagooffline-net (no compose labels)..."
    docker network rm chicagooffline-net 2>/dev/null || true
  fi
fi

# ── Reset DB if requested ────────────────────────────────────────────────────
if [ "${RESET_DB:-}" = "true" ]; then
  echo "⚠️  RESET_DB=true — wiping database..."
  docker compose -f "$COMPOSE_FILE" down -v --remove-orphans 2>/dev/null || true
fi

# ── Deploy ───────────────────────────────────────────────────────────────────
export CORESCOPE_FORK_DIR="$FORK_DIR"
export HEALTH_CHECK_DIR="./meshcore-health-check"
export LIVEMAP_DIR="./meshcore-mqtt-live-map"

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
  echo "📡 Matrix: https://observers-dev.chicagooffline.com"
else
  echo "🌐 Landing: https://chicagooffline.com"
  echo "📡 Scope:   https://scope.chicagooffline.com"
  echo "📻 MQTT:    mqtt://mqtt.chicagooffline.com:1883"
  echo "🩺 Health:  https://health.chicagooffline.com"
  echo "🔑 Keygen:  https://keygen.chicagooffline.com"
  echo "🗺️  LiveMap: https://livemap.chicagooffline.com"
  echo "📡 Matrix: https://observers.chicagooffline.com"
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
