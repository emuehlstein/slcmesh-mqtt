# Plan: Add WS MQTT Broker to Production

**Created:** 2026-04-23
**Status:** Implemented — deployed 2026-04-23

## Goal

Run `meshcore-mqtt-broker` (WebSocket MQTT) on prod alongside the existing standalone Mosquitto, so WS-capable observer firmware and mctomqtt clients can publish to prod via `wss://wsmqtt.chicagooffline.com/mqtt` with JWT auth.

## Current State

### Production (`13.58.181.117`)
```
[mosquitto]            standalone, port 1883 (TCP, no auth)
[corescope]            Go server, reads from mosquitto:1883
[caddy]                TLS/routing for all prod vhosts
[meshcore-health-check] port 3090
```

### Development (`3.141.31.229`)
```
[meshcore-mqtt-broker] WS broker, port 8883 (internal), JWT auth
[corescope-dev]        reads from meshcore-mqtt-broker:8883 via WS
[caddy]                TLS/routing, proxies wsmqtt-dev → broker:8883
```

## Target State (Production)

```
[mosquitto]              standalone, port 1883 (TCP, no auth) — UNCHANGED
[meshcore-mqtt-broker]   WS broker, port 8883 (internal), JWT auth — NEW
[corescope]              reads from BOTH mosquitto:1883 AND meshcore-mqtt-broker:8883
[caddy]                  adds wsmqtt.chicagooffline.com → broker:8883 — UPDATED
[meshcore-health-check]  port 3090 — UNCHANGED
```

Observers can connect via either:
- **TCP:** `mqtt://mqtt.chicagooffline.com:1883` (no auth, any firmware)
- **WSS:** `wss://wsmqtt.chicagooffline.com/mqtt` (JWT auth, WS firmware)

CoreScope deduplicates packets by content hash — same packet arriving from both brokers creates one transmission + separate observations.

## Changes Required

### 1. DNS (Route 53)

Add A record:
```
A    wsmqtt.chicagooffline.com    → 13.58.181.117    TTL 60
```

### 2. Caddyfile (prod)

Add vhost for WS broker:
```caddy
wsmqtt.chicagooffline.com {
    reverse_proxy meshcore-mqtt-broker:8883
}
```

Note: Caddy must proxy as HTTP/1.1 for WebSocket upgrade to work (Caddy does this by default for `reverse_proxy`).

### 3. deploy.sh

Change `WITH_MQTT_BROKER=false` → `WITH_MQTT_BROKER=true` for prod.

Update the broker env file section to use environment-specific audience:
```bash
AUTH_EXPECTED_AUDIENCE=wsmqtt.chicagooffline.com   # prod (currently hardcoded to wsmqtt-dev)
AUTH_EXPECTED_AUDIENCE=wsmqtt-dev.chicagooffline.com  # dev
```

The broker section already handles building, env file creation, and container startup — it just needs to run for prod too.

### 4. config.json (prod CoreScope)

Switch from legacy single `mqtt` field to `mqttSources` array with both brokers:

```json
{
  "mqttSources": [
    {
      "name": "mosquitto-tcp",
      "broker": "mqtt://mosquitto:1883",
      "topics": ["meshcore/#"]
    },
    {
      "name": "wsmqtt-ws",
      "broker": "ws://meshcore-mqtt-broker:8883/mqtt",
      "username": "corescope",
      "password": "BROKER_CORESCOPE_PASSWORD",
      "topics": ["meshcore/#"]
    }
  ]
}
```

Note: CoreScope connects to the WS broker internally via Docker network (no TLS needed — that's Caddy's job for external clients). Need to verify CoreScope's paho client supports `ws://` scheme.

### 5. GH Secrets (prod environment)

Add to `production` environment (if not already there):
- `BROKER_CORESCOPE_PASSWORD` — password for CoreScope subscriber account
- `BROKER_ADMIN_PASSWORD` — password for admin/debug account

### 6. deploy.sh — Broker env audience fix

The broker env file currently hardcodes `AUTH_EXPECTED_AUDIENCE=wsmqtt-dev.chicagooffline.com`. Needs to be dynamic:

```bash
if [ "$ENVIRONMENT" = "dev" ]; then
  BROKER_AUDIENCE="wsmqtt-dev.chicagooffline.com"
else
  BROKER_AUDIENCE="wsmqtt.chicagooffline.com"
fi
```

### 7. deploy.sh — Broker lifecycle (match Mosquitto pattern)

Like standalone Mosquitto, the WS broker should survive app deploys:
```bash
# Only create broker container if not already running
if docker inspect meshcore-mqtt-broker &>/dev/null && \
   [ "$(docker inspect -f '{{.State.Running}}' meshcore-mqtt-broker)" = "true" ]; then
  echo "✅ meshcore-mqtt-broker already running (not restarting)"
else
  # build + start broker
fi
```

Currently deploy.sh does `docker rm -f` on every deploy — same pattern we just fixed for Mosquitto.

### 8. config.json password injection

The `BROKER_CORESCOPE_PASSWORD` placeholder in config.json needs to be resolved at deploy time. Dev already does this with `sed`. Extend to prod:

```bash
# Inject broker password for both environments (not just dev)
if [ -n "${BROKER_CORESCOPE_PASSWORD:-}" ]; then
  sed "s/BROKER_CORESCOPE_PASSWORD/${BROKER_CORESCOPE_PASSWORD}/g" \
    "$CORESCOPE_CONFIG" > /tmp/corescope-config-resolved.json
  cp /tmp/corescope-config-resolved.json "$CORESCOPE_DATA_DIR/config.json"
else
  cp "$CORESCOPE_CONFIG" "$CORESCOPE_DATA_DIR/config.json"
fi
```

## Verification Steps

### Before cutover
- [ ] Verify CoreScope paho client handles `ws://` broker URLs (check `ResolvedSources()` in config.go)
- [ ] Set GH secrets for prod environment
- [ ] Create DNS record

### After deploy
- [ ] `docker ps` shows `meshcore-mqtt-broker` running on prod
- [ ] `curl -i https://wsmqtt.chicagooffline.com/` returns WS upgrade or broker redirect (confirms Caddy + TLS working)
- [ ] CoreScope logs show connections to both `mosquitto:1883` and `meshcore-mqtt-broker:8883`
- [ ] Observer on WS firmware can connect to `wsmqtt.chicagooffline.com` and packets appear in scope.chicagooffline.com
- [ ] Observer on standard firmware still connects via `mqtt.chicagooffline.com:1883` — no disruption
- [ ] Dedup stats: `DuplicateTransmissions` counter ticks up for packets seen on both brokers (expected)

## Risks

- **CoreScope WS support**: Need to verify paho-go handles `ws://` URLs. If not, the internal connection could use a different client or we proxy through Caddy internally (less ideal).
- **No MQTT downtime**: Mosquitto is untouched. WS broker is additive. CoreScope restart is the only blip (~5 sec, same as any deploy).
- **Secret management**: Prod environment needs the broker secrets added before deploy.
- **Health check MQTT**: Currently connects to `corescope:1883` (Mosquitto was inside CoreScope). Now needs to connect to `mosquitto:1883` (standalone container). This is already correct if running the latest deploy.sh, but worth verifying.

## Decisions

1. **WS broker survives deploys** — yes, same pattern as standalone Mosquitto.
2. **Abuse detection off** — test on dev first before enabling on prod.
3. **Same subscriber accounts** as dev (`corescope` + `admin`).

## Files to Modify

- `deploy.sh` — `WITH_MQTT_BROKER=true` for prod, dynamic audience, survive-deploy pattern
- `config.json` — switch to `mqttSources` array with both brokers
- `Caddyfile` — add `wsmqtt.chicagooffline.com` vhost
- Route 53 — add DNS A record
- GH `production` environment — add broker secrets

## Estimated Time: ~20 minutes (after answering open questions)
