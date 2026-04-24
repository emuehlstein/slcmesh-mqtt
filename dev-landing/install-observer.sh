#!/bin/bash
# ============================================================================
# Chicago Offline - MeshCore Observer Installer
#
# Detects your node type and runs the right upstream installer with
# pre-configured Chicago brokers.
#
# Usage:
#   bash <(curl -fsSL https://dev-landing.chicagooffline.com/install-observer.sh)
#
# Supports:
#   - Companions  (via agessaman/meshcore-packet-capture, no root)
#   - Repeaters   (via Cisien/meshcoretomqtt, requires sudo)
#   - Room Servers (via Cisien/meshcoretomqtt, requires sudo)
#
# Brokers configured:
#   - LetsMesh US  (mqtt-us-v1.letsmesh.net)
#   - LetsMesh EU  (mqtt-eu-v1.letsmesh.net)
#   - chimesh.org  (mqtt.chimesh.org)
#   - Chicago Offline prod (ws.chioff.com)
#   - Chicago Offline dev  (wsmqtt-dev.chicagooffline.com)
#
# IATA region: ORD (Chicago)
# ============================================================================
set -e

CONFIG_URL="https://dev-landing.chicagooffline.com/00-chicagooffline.toml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${BLUE}  Chicago Offline - MeshCore Observer Setup${NC}"
echo -e "${BLUE}  ==========================================${NC}"
echo ""
echo "  This will install an MQTT observer and configure it to report to:"
echo "    - LetsMesh US  (mqtt-us-v1.letsmesh.net)"
echo "    - LetsMesh EU  (mqtt-eu-v1.letsmesh.net)"
echo "    - chimesh.org  (mqtt.chimesh.org)"
echo "    - Chicago Offline prod (ws.chioff.com)"
echo "    - Chicago Offline dev  (wsmqtt-dev.chicagooffline.com)"
echo ""
echo "  IATA region: ORD (Chicago)"
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
    bash <(curl -fsSL https://raw.githubusercontent.com/agessaman/meshcore-packet-capture/main/install.sh) --config "$CONFIG_URL"
else
    echo -e "${GREEN}  Installing mctomqtt (repeaters/room servers)...${NC}"
    echo -e "  ${YELLOW}Root access required -- you may be prompted for your password.${NC}"
    echo ""
    curl -fsSL https://raw.githubusercontent.com/Cisien/meshcoretomqtt/main/install.sh | sudo bash -s -- --config "$CONFIG_URL"
fi

echo ""
echo -e "${GREEN}  Done! Your observer is configured for the Chicago Offline network.${NC}"
echo ""
