#!/bin/bash
# deploy-broker.sh — standalone deploy for meshcore-mqtt-broker on the dev box
# This script is NOT called by deploy.sh — run it manually only when the broker
# config changes or needs an update. The container uses restart:unless-stopped
# so it survives normal code deploys.
#
# Usage:
#   ./deploy-broker.sh           # deploy/update the broker
#   ./deploy-broker.sh --rebuild # force Docker image rebuild (upstream changes)
set -e

REBUILD=false
if [ "${1:-}" = "--rebuild" ]; then
  REBUILD=true
fi

BROKER_DIR="$(cd "$(dirname "$0")" && pwd)/meshcore-mqtt-broker"
ENV_FILE="$HOME/meshcore-mqtt-broker.env"
DATA_DIR="$HOME/meshcore-mqtt-broker-data"
NETWORK_NAME="chicagooffline-net"
IMAGE_NAME="meshcore-mqtt-broker:latest"
CONTAINER_NAME="meshcore-mqtt-broker"

echo "🔐 Deploying meshcore-mqtt-broker..."

# Check env file exists
if [ ! -f "$ENV_FILE" ]; then
  echo "❌ Missing $ENV_FILE"
  echo "   Copy meshcore-mqtt-broker/.env.example to $ENV_FILE on the server and fill in values."
  exit 1
fi

# Sanity check for placeholder passwords
if grep -q "CHANGE_ME" "$ENV_FILE"; then
  echo "❌ $ENV_FILE still has CHANGE_ME placeholders. Edit it first."
  exit 1
fi

# Ensure network exists
docker network inspect "$NETWORK_NAME" >/dev/null 2>&1 || docker network create "$NETWORK_NAME"

# Ensure data dir exists
mkdir -p "$DATA_DIR"

# Build image
if [ "$REBUILD" = true ] || ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
  echo "📦 Building $IMAGE_NAME..."
  docker build --no-cache -t "$IMAGE_NAME" "$BROKER_DIR"
else
  echo "✅ Image $IMAGE_NAME already exists (use --rebuild to force)"
fi

# Stop and remove existing container
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

# Start broker
docker run -d \
  --name "$CONTAINER_NAME" \
  --restart=unless-stopped \
  --env-file "$ENV_FILE" \
  -v "$DATA_DIR:/data" \
  --network "$NETWORK_NAME" \
  "$IMAGE_NAME"

echo ""
echo "✅ meshcore-mqtt-broker running"
echo "   Internal:  ws://meshcore-mqtt-broker:8883"
echo "   External:  wss://wsmqtt-dev.chicagooffline.com (via Caddy)"
echo ""
echo "Container logs:"
docker logs --tail 20 "$CONTAINER_NAME"
