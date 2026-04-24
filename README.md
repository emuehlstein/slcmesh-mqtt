# chicagooffline.com — MeshCore Infrastructure

MeshCore network tools for the Chicago (ORD) region.

## URLs

### Production (EC2: `13.58.181.117`)
| Service | URL |
|---------|-----|
| Landing Page | https://chicagooffline.com |
| Network Scope | https://scope.chicagooffline.com |
| Health Check | https://health.chicagooffline.com |
| MQTT Broker | `mqtt://mqtt.chicagooffline.com:1883` |
| WS MQTT Broker | `wss://wsmqtt.chicagooffline.com/mqtt` |

### Development (EC2: `3.141.31.229`)
| Service | URL |
|---------|-----|
| Landing Page | https://dev-landing.chicagooffline.com |
| Network Scope | https://dev-scope.chicagooffline.com |
| Health Check | https://dev-health.chicagooffline.com |
| Live Map | https://dev-livemap.chicagooffline.com |
| Keygen | https://dev-keygen.chicagooffline.com |
| WS MQTT Broker | `wss://wsmqtt-dev.chicagooffline.com/mqtt` |

### Map Tile Server (EC2: `3.20.103.82`)
| Service | URL |
|---------|-----|
| Tile Server | https://tiles.chicagooffline.com |

## Architecture

### Production Stack
```
chicagooffline.com (EC2 t3.small, 13.58.181.117)
├── Caddy (TLS + routing, ports 80/443)
│   ├── chicagooffline.com         → /srv/landing (static)
│   ├── scope.chicagooffline.com   → corescope:3000
│   ├── health.chicagooffline.com  → meshcore-health-check:3090
│   └── wsmqtt.chicagooffline.com  → meshcore-mqtt-broker:8883
├── CoreScope (Go, port 3000)
│   ├── Built from emuehlstein/CoreScope-chicagooffline (deploy/chicagooffline branch)
│   ├── MQTT client → local Mosquitto
│   └── SQLite database (persistent volume)
├── Mosquitto (MQTT, port 1883 exposed)
├── meshcore-mqtt-broker (WSS MQTT, JWT auth, port 8883 internal)
├── meshcore-health-check (port 3090 internal)
└── Docker network: chicagooffline-net
```

### Development Stack
```
dev EC2 (t3.small, 3.141.31.229)
├── Caddy (TLS + routing, ports 80/443)
│   ├── dev-landing.chicagooffline.com  → /srv/dev-landing (static)
│   ├── dev-scope.chicagooffline.com    → corescope-dev:3000
│   ├── dev-health.chicagooffline.com   → meshcore-health-check-dev:3091
│   ├── dev-livemap.chicagooffline.com  → meshmap-live:8080
│   ├── dev-keygen.chicagooffline.com   → /srv/keygen (static)
│   └── wsmqtt-dev.chicagooffline.com   → meshcore-mqtt-broker:8883
├── corescope-dev (Go, port 3000)
├── Mosquitto (MQTT, port 1883)
├── meshcore-mqtt-broker (WSS MQTT, JWT auth)
├── meshcore-health-check-dev (port 3091 internal)
├── meshmap-live (Live Map, port 8080 internal)
│   └── yellowcooln/meshcore-mqtt-live-map
└── Docker network: chicagooffline-net
```

## Deployment

### Branch Strategy
| Branch | Triggers | Environment |
|--------|----------|-------------|
| `main` | auto on push | **dev** only |
| `prod` | auto on push | **production** only |
| `workflow_dispatch` | manual | your choice |

**Push to `main`** → deploys to dev. Safe for iterating.

**Promote dev → prod:**
```bash
git checkout prod && git merge main && git push && git checkout main
```

**Manual deploy (either environment):**
```bash
gh workflow run deploy.yml -f environment=dev
gh workflow run deploy.yml -f environment=production
gh workflow run deploy.yml -f environment=dev -f reset_db=true  # wipe DB
```

### GitHub Secrets (per environment)
| Secret | Prod | Dev | Notes |
|--------|------|-----|-------|
| `SSH_PRIVATE_KEY` | ✅ | ✅ | EC2 SSH key |
| `SSH_HOST` | `13.58.181.117` | `3.141.31.229` | EC2 IP |
| `SSH_USER` | `ubuntu` | `ubuntu` | |
| `DEPLOY_KEY` | ✅ | ✅ | ed25519 deploy key for git clone |
| `CARTOGRAPHER_HEALTHCHECK_KEY` | ✅ | ✅ | Health check channel secret |
| `BROKER_CORESCOPE_PASSWORD` | ✅ | ✅ | MQTT broker subscriber password |
| `BROKER_ADMIN_PASSWORD` | ✅ | ✅ | MQTT broker admin password |

### What Deploy Does
1. SSHs into the target EC2
2. Clones/pulls `chimesh-mqtt` repo via deploy key
3. Clones/pulls `CoreScope-chicagooffline` fork (`deploy/chicagooffline` branch)
4. Builds CoreScope Docker image (`--no-cache`)
5. Clones/pulls `meshcore-web-keygen` (static files → `/srv/keygen`)
6. Clones/pulls `meshcore-mqtt-live-map`, builds + starts container
7. Starts all containers on shared Docker network
8. Caddy auto-provisions TLS certs via Let's Encrypt

## CoreScope Fork

Built from [emuehlstein/CoreScope-chicagooffline](https://github.com/emuehlstein/CoreScope-chicagooffline) on the `deploy/chicagooffline` branch.

Customizations:
- Chicago-themed dark UI with custom color palette
- Hillshade map layer (combined 3DEP+LiDAR 9x tiles from `tiles.chicagooffline.com`)
- Retro modem audio voice module
- Custom config/theme overlays

### Configs
- `config.json` — Production CoreScope config
- `dev-config.json` — Dev CoreScope config
- `dev-theme.json` — Dev theme overrides
- `Caddyfile` — Production Caddy routes
- `Caddyfile.dev` — Dev Caddy routes

## Third-Party Tools

### meshcore-mqtt-live-map
- **Repo:** [yellowcooln/meshcore-mqtt-live-map](https://github.com/yellowcooln/meshcore-mqtt-live-map)
- **Purpose:** Live MQTT-fed node map with routes, weather, LOS analysis
- **URL:** https://dev-livemap.chicagooffline.com
- **Config:** `~/meshcore-mqtt-live-map/.env` on dev EC2

### meshcore-web-keygen
- **Repo:** [agessaman/meshcore-web-keygen](https://github.com/agessaman/meshcore-web-keygen)
- **Purpose:** Client-side MeshCore Ed25519 vanity key generator
- **URL:** https://dev-keygen.chicagooffline.com
- **Static site:** no backend needed

### meshcore-mqtt-broker
- **Repo:** [michaelhart/meshcore-mqtt-broker](https://github.com/michaelhart/meshcore-mqtt-broker)
- **Purpose:** WebSocket MQTT broker with JWT auth via MeshCore device keys
- **Auth:** Ed25519 signatures, `v1_{PUBKEY}` username format

## Connecting Observer Nodes

### Plain TCP (Production)
```
Server: mqtt.chicagooffline.com
Port:   1883
Topic:  meshcore/ORD/<node-pubkey>/packets
Auth:   none
```

### WebSocket + JWT (Dev)
```
Server: wsmqtt-dev.chicagooffline.com
Port:   443
Path:   /mqtt
TLS:    yes
Topic:  meshcore/ORD/<node-pubkey>/packets
Auth:   JWT (Ed25519 device key)
```

For `mctomqtt` config, see `OBSERVER_SETUP.md`.

## DNS Records (Route 53)

**Hosted Zone:** `Z0192662J0UU9ADD406Z`

### Production → 13.58.181.117
```
chicagooffline.com
scope.chicagooffline.com
mqtt.chicagooffline.com
health.chicagooffline.com
healthcheck.chicagooffline.com
wsmqtt.chicagooffline.com
```

### Development → 3.141.31.229
```
dev-scope.chicagooffline.com
dev-landing.chicagooffline.com
dev-health.chicagooffline.com
dev-keygen.chicagooffline.com
dev-livemap.chicagooffline.com
wsmqtt-dev.chicagooffline.com
```

### Tile Server → 3.20.103.82
```
tiles.chicagooffline.com
```

## Monitoring

```bash
# Production
ssh -i ~/.ssh/chicagooffline-ec2.pem ubuntu@13.58.181.117
docker ps
docker logs -f corescope

# Development
ssh -i ~/.ssh/chicagooffline-dev.pem ubuntu@3.141.31.229
docker ps
docker logs -f corescope-dev
docker logs -f meshmap-live
```

## Maintenance

### Disk Space (Prod is 6.8GB — watch it)
```bash
ssh -i ~/.ssh/chicagooffline-ec2.pem ubuntu@13.58.181.117
df -h /
docker system prune -af    # remove unused images + build cache
```

### Stop/Start Dev Instance
```bash
# Stop (saves money when not testing)
aws ec2 stop-instances --region us-east-2 --instance-ids i-015964acf101b916d

# Start (IP may change — update DNS + GitHub secret)
aws ec2 start-instances --region us-east-2 --instance-ids i-015964acf101b916d
```

### Wipe Dev Database
```bash
gh workflow run deploy.yml -f environment=dev -f reset_db=true
```

## Cost
| Resource | Monthly |
|----------|---------|
| Prod EC2 (t3.small, always on) | ~$15 |
| Dev EC2 (t3.small, stop when idle) | ~$0-15 |
| Tile server (t4g.small, always on) | ~$12 |
| Route 53 | ~$0.50 |
| Data transfer | ~$1-5 |
| **Total** | **~$30-48** |
