#!/bin/bash
# ============================================================================
# Chicago Offline - MeshCore Observer Installer
# Wraps the upstream mctomqtt installer with pre-configured Chicago brokers.
#
# Usage:
#   bash <(curl -fsSL https://dev-landing.chicagooffline.com/install-observer.sh)
#
# What this does:
#   1. Runs the official mctomqtt installer (serial/BLE detection, venv, service)
#   2. Drops in a config with LetsMesh US, chimesh.org, and chicagooffline.com
#   3. Sets IATA to ORD (Chicago)
#
# You'll still need to:
#   - Select your serial port or BLE device during install
#   - Set WiFi credentials on native-uplink firmware (if applicable)
# ============================================================================
set -e

CONFIG_URL="https://dev-landing.chicagooffline.com/00-chicagooffline.toml"

echo ""
echo "  Chicago Offline - MeshCore Observer Setup"
echo "  =========================================="
echo ""
echo "  This will install mctomqtt and configure it to report to:"
echo "    - LetsMesh US  (mqtt-us-v1.letsmesh.net)"
echo "    - LetsMesh EU  (mqtt-eu-v1.letsmesh.net)"
echo "    - chimesh.org  (mqtt.chimesh.org)"
echo "    - Chicago Offline prod (ws.chioff.com)"
echo "    - Chicago Offline dev  (wsmqtt-dev.chicagooffline.com)"
echo ""
echo "  IATA region: ORD (Chicago)"
echo ""

# Run the upstream mctomqtt installer with our config
curl -fsSL https://raw.githubusercontent.com/Cisien/meshcoretomqtt/main/install.sh | bash -s -- --config "$CONFIG_URL"
