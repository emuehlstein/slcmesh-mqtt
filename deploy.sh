#!/bin/bash
set -e

echo "🚀 Deploying CoreScope to chicagooffline.com..."

# Stop existing container if running
docker stop corescope 2>/dev/null || true
docker rm corescope 2>/dev/null || true

# Pull latest image
docker pull ghcr.io/kpa-clawbot/corescope:latest

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
  ghcr.io/kpa-clawbot/corescope:latest

echo "✅ CoreScope deployed!"
echo "🌐 Web UI: https://chicagooffline.com"
echo "📡 MQTT: mqtt://mqtt.chicagooffline.com:1883"

# Show logs
docker logs -f corescope
