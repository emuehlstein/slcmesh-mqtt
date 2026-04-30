#!/bin/bash
# ============================================================================
# Salt Lake Offline - MeshCore Observer Installer
#
# Detects your node type and runs the right upstream installer with
# pre-configured Salt Lake City brokers.
#
# Usage:
#   bash <(curl -fsSL https://dev-landing.slcoffline.com/install-observer.sh)
#
# Supports:
#   - Companions  (via agessaman/meshcore-packet-capture, no root)
#   - Repeaters   (via Cisien/meshcoretomqtt, requires sudo)
#   - Room Servers (via Cisien/meshcoretomqtt, requires sudo)
#
# Brokers configured (priority order):
#   1. LetsMesh US  (mqtt-us-v1.letsmesh.net:443, WebSocket, JWT)
#   2. chimesh.org  (mqtt.chimesh.org:443, WebSocket, JWT)
#   3. Salt Lake Offline prod (wsmqtt.slcoffline.com:443, WebSocket, JWT)
#   4. Salt Lake Offline dev  (wsmqtt-dev.slcoffline.com:443, WebSocket, JWT)
#   5. rflab.io     (mqtt.rflab.io:443, WebSocket, JWT)
#   6. LetsMesh EU  (mqtt-eu-v1.letsmesh.net:443, WebSocket, JWT)
#   7. Salt Lake Offline TCP fallback (mqtt.slcoff.com:1883, TCP, no auth)
#
# IATA region: SLC (Salt Lake City)
# ============================================================================
set -e

CONFIG_TOML="https://dev-landing.slcoffline.com/00-slcland.toml"
CONFIG_ENV="https://dev-landing.slcoffline.com/00-slcland.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${BLUE}  Salt Lake Offline - MeshCore Observer Setup${NC}"
echo -e "${BLUE}  ==========================================${NC}"
echo ""
echo "  This will install an MQTT observer and configure it to report to:"
echo "    1. LetsMesh US  (mqtt-us-v1.letsmesh.net:443)"
echo "    2. chimesh.org  (mqtt.chimesh.org:443)"
echo "    3. Salt Lake Offline prod (wsmqtt.slcoffline.com:443)"
echo "    4. Salt Lake Offline dev  (wsmqtt-dev.slcoffline.com:443)"
echo "    5. rflab.io     (mqtt.rflab.io:443)"
echo "    6. LetsMesh EU  (mqtt-eu-v1.letsmesh.net:443)"
echo "    7. Salt Lake Offline TCP fallback (mqtt.slcoff.com:1883, no auth)"
echo ""
echo "  IATA region: SLC (Salt Lake City)"
echo ""
echo -e "${BOLD}  What type of node are you connecting?${NC}"
echo ""
echo "    1) Companion  (handheld/personal device)"
echo "    2) Repeater   (relay node)"
echo "    3) Room Server"
echo ""

while true; do
    read -rp "  Select [1-3]: " choice
    case $choice in
        1)
            NODE_TYPE="companion"
            break
            ;;
        2)
            NODE_TYPE="repeater"
            break
            ;;
        3)
            NODE_TYPE="roomserver"
            break
            ;;
        *)
            echo -e "  ${RED}Invalid choice. Enter 1, 2, or 3.${NC}"
            ;;
    esac
done

echo ""

if [ "$NODE_TYPE" = "companion" ]; then
    echo -e "${GREEN}  Installing meshcore-packet-capture (companions)...${NC}"
    echo -e "  ${BLUE}No root required.${NC}"
    echo ""
    bash <(curl -fsSL https://raw.githubusercontent.com/agessaman/meshcore-packet-capture/main/install.sh) --config "$CONFIG_ENV"
else
    echo -e "${GREEN}  Installing mctomqtt (repeaters/room servers)...${NC}"
    echo -e "  ${YELLOW}Root access required -- you may be prompted for your password.${NC}"
    echo ""
    curl -fsSL https://raw.githubusercontent.com/Cisien/meshcoretomqtt/main/install.sh | sudo bash -s -- --config "$CONFIG_TOML"
fi

echo ""
echo -e "${GREEN}  Done! Your observer is configured for the Salt Lake Offline network.${NC}"
echo ""
