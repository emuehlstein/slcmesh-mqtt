# Plan: Split Mosquitto into Standalone Container

**Created:** 2026-04-22
**Status:** Implemented — deployed 2026-04-23

## Problem
- Mosquitto runs inside the CoreScope container via supervisord
- Restarting CoreScope (for code updates, config changes, crashes) kills MQTT
- Observer nodes lose connection and need to reconnect
- Can't independently scale/monitor/restart MQTT vs the web app
- Prod and dev share the same physical MQTT broker (only prod maps port 1883)

## Current Architecture

```
[corescope container] (supervisord)
├── corescope-server    (Go, port 3000)
├── corescope-ingestor  (Go, connects to localhost:1883)
└── mosquitto           (port 1883, mapped to host)
```

- Prod container (`corescope`): DISABLE_MOSQUITTO=false, port 1883 mapped
- Dev container (`corescope-dev`): DISABLE_MOSQUITTO=true, port 1883 not mapped
- Both on `chicagooffline-net` Docker network
- Both on same EC2 host (13.58.181.117 = prod, 3.141.31.229 = dev)

## Target Architecture

```
[mosquitto container]       (standalone, always running)
└── mosquitto               (port 1883, mapped to host)

[corescope container]       (restartable independently)
├── corescope-server        (Go, port 3000)
└── corescope-ingestor      (Go, connects to mosquitto:1883 via Docker network)

[corescope-dev container]   (restartable independently)  
├── corescope-server        (Go, port 3000)
└── corescope-ingestor      (Go, connects to mosquitto:1883 via Docker network)
```

## Phase 1: Standalone Mosquitto Container (prod)

1. **Create mosquitto config** (`mosquitto/mosquitto.conf` in repo):
   - Copy existing config from CoreScope's `docker/mosquitto.conf`
   - Listener on 1883 (plain TCP)
   - Persistence enabled at `/mosquitto/data`
   - Logging to stdout

2. **Add standalone mosquitto to deploy.sh**:
   ```bash
   docker run -d --name mosquitto \
     --restart=unless-stopped \
     -p 1883:1883 \
     -v ~/mosquitto-data:/mosquitto/data \
     -v ~/chimesh-mqtt/mosquitto/mosquitto.conf:/mosquitto/config/mosquitto.conf:ro \
     --network chicagooffline-net \
     eclipse-mosquitto:2
   ```

3. **Update CoreScope containers**: Set `DISABLE_MOSQUITTO=true` for BOTH prod and dev

4. **Update ingestor MQTT config**: In `config.json` and `dev-config.json`, change MQTT server from `localhost:1883` to `mosquitto:1883` (Docker DNS resolves container names on shared network)

## Phase 2: Update deploy.sh

1. **Mosquitto lifecycle**: Only restart if mosquitto.conf changed or container missing
   ```bash
   # Only recreate mosquitto if config changed or not running
   if ! docker inspect mosquitto &>/dev/null; then
     # start mosquitto container
   fi
   ```

2. **CoreScope lifecycle**: Restart freely without affecting MQTT
   - Remove mosquitto-related env vars and port mappings from CoreScope containers
   - Remove `DISABLE_MOSQUITTO` env var entirely (no more supervisord mosquitto)

3. **Health check**: Verify MQTT is reachable before starting ingestor
   ```bash
   docker exec mosquitto mosquitto_pub -t test -m "healthcheck" -q 0
   ```

## Phase 3: Verify & Cutover

### Test on Dev First
1. Deploy standalone mosquitto on dev EC2 (3.141.31.229)
2. Restart CoreScope-dev with DISABLE_MOSQUITTO=true
3. Verify ingestor connects to mosquitto:1883 via Docker network
4. Verify observer nodes reconnect to mqtt.chicagooffline.com:1883

### Cutover on Prod
1. Start standalone mosquitto container on prod (13.58.181.117)
2. Stop old corescope container (brief MQTT blip, ~5-10 sec)
3. Start new corescope container with DISABLE_MOSQUITTO=true
4. Verify mqtt.chicagooffline.com:1883 still works from observer nodes
5. Verify CoreScope ingestor reconnects and receives packets

## Risks

- **Brief MQTT downtime** during cutover (~5-10 sec)
- Observer nodes should auto-reconnect (MeshCore firmware handles reconnection)
- Need to verify mosquitto.conf settings are preserved (listeners, auth, ACLs)
- Port 1883 ownership moves from corescope container to mosquitto container

## Files to Modify

- `deploy.sh` — add mosquitto container, update CoreScope container config
- `config.json` — change MQTT server to `mosquitto:1883`
- `dev-config.json` — change MQTT server to `mosquitto:1883`
- New: `mosquitto/mosquitto.conf` — standalone config

## Estimated Time: ~30 minutes
