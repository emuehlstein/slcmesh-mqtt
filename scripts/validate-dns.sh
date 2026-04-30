#!/bin/bash
set -e

# validate-dns.sh — Verify chicagooffline.com DNS zone state
# Run before deploys to ensure zone matches desired state
# Usage: ./scripts/validate-dns.sh [--fix]

set -e

ZONE_ID="Z0192662J0UU9ADD406Z"

# Desired state: name -> ip
declare -A DESIRED_PROD
DESIRED_PROD["chicagooffline.com"]="13.58.181.117"
DESIRED_PROD["scope.chicagooffline.com"]="13.58.181.117"
DESIRED_PROD["health.chicagooffline.com"]="13.58.181.117"
DESIRED_PROD["healthcheck.chicagooffline.com"]="13.58.181.117"
DESIRED_PROD["mqtt.chicagooffline.com"]="13.58.181.117"
DESIRED_PROD["wsmqtt.chicagooffline.com"]="13.58.181.117"
DESIRED_PROD["keygen.chicagooffline.com"]="13.58.181.117"
DESIRED_PROD["livemap.chicagooffline.com"]="13.58.181.117"

declare -A DESIRED_DEV
DESIRED_DEV["dev-scope.chicagooffline.com"]="3.141.31.229"
DESIRED_DEV["dev-landing.chicagooffline.com"]="3.141.31.229"
DESIRED_DEV["dev-health.chicagooffline.com"]="3.141.31.229"
DESIRED_DEV["dev-mqtt.chicagooffline.com"]="3.141.31.229"
DESIRED_DEV["dev-wsmqtt.chicagooffline.com"]="3.141.31.229"
DESIRED_DEV["dev-keygen.chicagooffline.com"]="3.141.31.229"
DESIRED_DEV["dev-livemap.chicagooffline.com"]="3.141.31.229"
DESIRED_DEV["dev-observers.chicagooffline.com"]="3.141.31.229"

declare -A DESIRED_MAP
DESIRED_MAP["tiles.chicagooffline.com"]="3.20.103.82"

# Forbidden records (should not exist)
FORBIDDEN=(
  "chimesh.chicagooffline.com"
  "observers-dev.chicagooffline.com"
)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

FIX_MODE="${1:-}"
ERRORS=0

echo "📡 Validating DNS zone $ZONE_ID..."
echo ""

# Fetch current zone
CURRENT=$(aws route53 list-resource-record-sets --hosted-zone-id "$ZONE_ID" --output json)

check_record() {
  local name="$1"
  local expected_ip="$2"
  local category="$3"
  
  local current_ip=$(echo "$CURRENT" | jq -r ".ResourceRecordSets[] | select(.Name == \"$name.\") | select(.Type == \"A\") | .ResourceRecords[0].Value" 2>/dev/null || echo "")
  
  if [ -z "$current_ip" ]; then
    echo -e "${RED}✗${NC} MISSING: $name (expected $expected_ip) [$category]"
    ((ERRORS++))
  elif [ "$current_ip" != "$expected_ip" ]; then
    echo -e "${RED}✗${NC} MISMATCH: $name → $current_ip (expected $expected_ip) [$category]"
    ((ERRORS++))
  else
    echo -e "${GREEN}✓${NC} $name → $current_ip [$category]"
  fi
}

check_forbidden() {
  local name="$1"
  local current_ip=$(echo "$CURRENT" | jq -r ".ResourceRecordSets[] | select(.Name == \"$name.\") | select(.Type == \"A\") | .ResourceRecords[0].Value" 2>/dev/null || echo "")
  
  if [ -n "$current_ip" ]; then
    echo -e "${RED}✗${NC} FORBIDDEN: $name exists ($current_ip) — should be deleted"
    ((ERRORS++))
  else
    echo -e "${GREEN}✓${NC} $name (correctly absent)"
  fi
}

echo "PROD Records:"
for name in "${!DESIRED_PROD[@]}"; do
  check_record "$name" "${DESIRED_PROD[$name]}" "PROD"
done
echo ""

echo "DEV Records:"
for name in "${!DESIRED_DEV[@]}"; do
  check_record "$name" "${DESIRED_DEV[$name]}" "DEV"
done
echo ""

echo "MAP Records:"
for name in "${!DESIRED_MAP[@]}"; do
  check_record "$name" "${DESIRED_MAP[$name]}" "MAP"
done
echo ""

echo "Forbidden Records (should not exist):"
for name in "${FORBIDDEN[@]}"; do
  check_forbidden "$name"
done
echo ""

if [ "$ERRORS" -eq 0 ]; then
  echo -e "${GREEN}✓ Zone is valid${NC}"
  exit 0
else
  echo -e "${RED}✗ $ERRORS errors found${NC}"
  if [ "$FIX_MODE" = "--fix" ]; then
    echo ""
    echo -e "${YELLOW}⚠ Auto-fix not yet implemented. Please fix manually.${NC}"
  fi
  exit 1
fi
