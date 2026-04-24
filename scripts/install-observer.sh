#!/bin/bash
# ============================================================================
# Chicago Offline - MeshCore Observer Installer
# Wraps the upstream meshcore-packet-capture installer with pre-configured
# Chicago brokers.
#
# Usage:
#   bash <(curl -fsSL https://dev-landing.chicagooffline.com/install-observer.sh)
#
# What this does:
#   1. Runs agessaman's meshcore-packet-capture installer
#      (serial/BLE detection, Python venv, service setup)
#   2. Drops in a config with LetsMesh US/EU, chimesh.org, and chioff prod/dev
#   3. Sets IATA to ORD (Chicago)
#
# You'll still need to:
#   - Select your serial port or BLE device during install
#   - Set WiFi credentials on native-uplink firmware (if applicable)
#
# No root required (installs to userspace).
# ============================================================================
set -e

CONFIG_URL="https://dev-landing.chicagooffline.com/00-chicagooffline.toml"

echo ""
echo "  Chicago Offline - MeshCore Observer Setup"
echo "  =========================================="
echo ""
echo "  This will install meshcore-packet-capture and configure it to report to:"
echo "    - LetsMesh US  (mqtt-us-v1.letsmesh.net)"
echo "    - LetsMesh EU  (mqtt-eu-v1.letsmesh.net)"
echo "    - chimesh.org  (mqtt.chimesh.org)"
echo "    - Chicago Offline prod (ws.chioff.com)"
echo "    - Chicago Offline dev  (wsmqtt-dev.chicagooffline.com)"
echo ""
echo "  IATA region: ORD (Chicago)"
echo ""

# Run agessaman's meshcore-packet-capture installer with our config
bash <(curl -fsSL https://raw.githubusercontent.com/agessaman/meshcore-packet-capture/main/install.sh) --config "$CONFIG_URL"
