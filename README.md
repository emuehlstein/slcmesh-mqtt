# chicagooffline.com - CoreScope Deployment

MeshCore network analyzer for Chicago (ORD region).

## URLs

### Production
- **Landing Page:** https://chicagooffline.com
- **Network Scope:** https://scope.chicagooffline.com
- **MQTT Broker:** mqtt://mqtt.chicagooffline.com:1883
- **Health Check:** https://health.chicagooffline.com | https://healthcheck.chicagooffline.com

### Development
- **Network Scope:** https://dev-scope.chicagooffline.com
- **Landing Page:** https://dev-landing.chicagooffline.com
- **WS MQTT Broker:** wss://wsmqtt-dev.chicagooffline.com/mqtt

## Infrastructure

### Production Environment
- **Instance:** t3.small (us-east-2)
- **IP:** 13.58.181.117
- **Services:**
  - External Caddy (TLS/routing)
  - CoreScope (Go server on port 3000, internal)
  - Mosquitto MQTT broker (port 1883)
  - Mesh Health Check (port 3090, internal)

### Development Environment
- **Instance:** t3.small (us-east-2)
- **IP:** 3.141.31.229
- **Services:**
  - External Caddy (TLS/routing)
  - `corescope-dev` container (Go server on port 3000, internal)
  - `meshcore-mqtt-broker` container (michaelhart/meshcore-mqtt-broker) — WebSocket MQTT broker
  - **MQTT:** Dev CoreScope subscribes to local WS broker (`wss://wsmqtt-dev.chicagooffline.com/mqtt`)
  - **No Health Check** — dev is for CoreScope UI/backend testing only

## Architecture

### Production Stack
```
chicagooffline.com (EC2 t3.small, 13.58.181.117)
├── External Caddy Container (TLS + routing)
│   ├── chicagooffline.com → Landing page (static files)
│   ├── scope.chicagooffline.com → CoreScope (:3000)
│   ├── health.chicagooffline.com → Health Check (:3090)
│   └── mqtt.chicagooffline.com:1883 → Mosquitto
├── CoreScope Container
│   ├── Mosquitto MQTT broker (port 1883)
│   ├── Go backend + packet store (port 3000, internal)
│   └── SQLite database (persistent volume)
├── Mesh Health Check Container (port 3090, internal)
└── Docker network: chicagooffline-net
```

### Development Stack
```
dev-scope.chicagooffline.com (EC2 t3.small, 3.141.31.229)
├── External Caddy Container (TLS + routing)
│   ├── dev-landing.chicagooffline.com → Landing page
│   ├── dev-scope.chicagooffline.com → CoreScope (:3000)
│   └── wsmqtt-dev.chicagooffline.com → meshcore-mqtt-broker (WSS)
├── corescope-dev Container
│   ├── Go backend + packet store (port 3000, internal)
│   ├── MQTT client → wss://wsmqtt-dev.chicagooffline.com/mqtt (local WS broker)
│   └── SQLite database (ephemeral, wiped on redeploy)
├── meshcore-mqtt-broker Container (michaelhart/meshcore-mqtt-broker)
│   ├── WebSocket MQTT over WSS
│   ├── JWT auth via Ed25519 device keys (v1_{PUBKEY} username format)
│   └── Subscriber accounts: corescope (read), admin (debug)
└── Docker network: chicagooffline-net
```

## Deployment

### Automated (GitHub Actions)
- **Push to `main`** → deploys to **production**
- **Push to `dev`** → deploys to **development**
- **Manual workflow dispatch** → choose environment + optional DB reset

**Required GitHub Secrets (per environment):**
- `SSH_PRIVATE_KEY` - Private key for EC2 access
- `SSH_HOST` - EC2 IP (13.58.181.117 for prod, 3.141.31.229 for dev)
- `SSH_USER` - `ubuntu`
- `DEPLOY_KEY` - ed25519 deploy key for git clone
- `CARTOGRAPHER_HEALTHCHECK_KEY` - Health Check channel secret (prod only)
- `BROKER_CORESCOPE_PASSWORD` - Password for `corescope` subscriber account (dev only)
- `BROKER_ADMIN_PASSWORD` - Password for `admin` debug account (dev only)

### Manual Deployment
SSH into EC2 and run:
```bash
cd ~/chimesh-mqtt
git pull origin main  # or dev
ENVIRONMENT=production bash deploy.sh  # or ENVIRONMENT=dev
```

### Deploy Script Features
- Detects environment from `ENVIRONMENT` var or branch name
- Installs Docker if missing (via user-data bootstrap on fresh instances)
- Builds CoreScope from chicagooffline fork (`CORESCOPE_IMAGE_MODE=fork`)
- Configures vhosts, MQTT sources, and data directories per environment
- Handles TLS cert generation via Caddy ACME

## Configuration

### Environment-Specific Configs

#### Production (`deploy.sh` defaults)
```bash
SCOPE_VHOST="scope.chicagooffline.com"
LANDING_VHOST="chicagooffline.com"
CORESCOPE_CONFIG="config.json"
WITH_MQTT=true              # Run local Mosquitto broker
WITH_HEALTH_CHECK=true      # Run mesh-health-check container
WITH_LANDING=true           # Serve landing page
DEV_BANNER=false            # No "DEV" banner
```

#### Development (`ENVIRONMENT=dev`)
```bash
SCOPE_VHOST="dev-scope.chicagooffline.com"
LANDING_VHOST="dev-landing.chicagooffline.com"
CORESCOPE_CONFIG="dev-config.json"
WITH_MQTT=true              # Connect to local WS broker
WITH_MQTT_BROKER=true       # Deploy meshcore-mqtt-broker container
WITH_HEALTH_CHECK=false     # No health check in dev
WITH_LANDING=true           # Serve landing page
DEV_BANNER=true             # Show "DEV" banner in UI
# Data dir: $HOME/corescope-dev-data
# Container name: corescope-dev
```

> **Standalone broker deploy:** Use `bash deploy-broker.sh` to redeploy only the `meshcore-mqtt-broker` container without touching CoreScope.

### CoreScope Configs

#### `config.json` (Production)
- MQTT broker: `mqtt://corescope:1883` (local container)
- Channel keys: `#public`, `#atak`, `#wardriving`, `#test`, `#healthcheck`
- Region: `ORD`
- Map center: Chicago (41.8781, -87.6298)

#### `dev-config.json` (Development)
- MQTT broker: `wss://wsmqtt-dev.chicagooffline.com/mqtt` (local WS broker)
- Auth: JWT via Ed25519 device keys (username: `v1_{PUBKEY}`)
- Channel keys: same as prod
- Region: `ORD`
- Map center: Chicago

### Caddyfile
External Caddy handles TLS + routing for all vhosts. Lives in repo root, mounted into Caddy container.

**Production routes:**
- `chicagooffline.com` → Landing page (`/srv/landing`)
- `scope.chicagooffline.com` → CoreScope (`:3000`)
- `health.chicagooffline.com` / `healthcheck.chicagooffline.com` → Health Check (`:3090`)

**Development routes:**
- `dev-landing.chicagooffline.com` → Landing page (`/srv/landing`)
- `dev-scope.chicagooffline.com` → CoreScope (`:3000`)

### Mesh Health Check Environment
On first deploy, `deploy.sh` creates `~/meshcore-health-check/.env` with defaults.

**Production-only** (`WITH_HEALTH_CHECK=true`):
- `TEST_CHANNEL_NAME` - channel used for health-check test messages
- `TEST_CHANNEL_SECRET` - channel secret (set via `HC_SECRET` env var in deploy)
- `TURNSTILE_ENABLED` - set to `1` if you want Cloudflare Turnstile protection

## Connecting Observer Nodes

Point your observer nodes (meshcoretomqtt, meshcore-packet-capture, or native firmware) to:
```
mqtt://mqtt.chicagooffline.com:1883
topic: meshcore/ORD/<node-pubkey>/packets
```

No authentication required (for now).

Two methods are supported:

### Method 1: Plain TCP (Production)
```
mqtt://mqtt.chicagooffline.com:1883
topic: meshcore/ORD/<node-pubkey>/packets
```
No authentication required. Works with any standard firmware or `mctomqtt`.

### Method 2: WebSocket + JWT (Dev)
```
wss://wsmqtt-dev.chicagooffline.com/mqtt
topic: meshcore/ORD/<node-pubkey>/packets
```
Requires WS-capable firmware (see [Firmware Fork](#firmware-fork-ws-custom-broker)) or `mctomqtt` with WS support.
JWT auth uses Ed25519 device keys — username format: `v1_{PUBKEY}`.

See `OBSERVER_SETUP.md` for detailed per-method configuration.

## Monitoring

### Production
```bash
ssh ubuntu@13.58.181.117 -i ~/.ssh/chicagooffline.pem

# View logs
docker logs -f corescope
docker logs -f caddy
docker logs -f mosquitto
docker logs -f meshcore-health-check

# Check status
docker ps

# Restart services
docker restart corescope
docker restart caddy
```

### Development
```bash
ssh ubuntu@3.141.31.229 -i ~/.ssh/chicagooffline-dev.pem

# View logs
docker logs -f corescope-dev
docker logs -f caddy
docker logs -f meshcore-mqtt-broker

# Check status
docker ps

# Restart
docker restart corescope-dev
docker restart meshcore-mqtt-broker
```

## DNS Records (Route 53)

**Hosted Zone:** `Z0192662J0UU9ADD406Z`

### Production (13.58.181.117)
```
A    chicagooffline.com                → 13.58.181.117
A    scope.chicagooffline.com          → 13.58.181.117
A    mqtt.chicagooffline.com           → 13.58.181.117
A    health.chicagooffline.com         → 13.58.181.117
A    healthcheck.chicagooffline.com    → 13.58.181.117
```

### Development (3.141.31.229)
```
A    dev-scope.chicagooffline.com      → 3.141.31.229
A    dev-landing.chicagooffline.com    → 3.141.31.229
A    wsmqtt-dev.chicagooffline.com     → 3.141.31.229
```

**TTL:** 60s for all records (allows fast IP updates during troubleshooting)

## Maintenance

### Update CoreScope
```bash
# Production
ssh ubuntu@13.58.181.117
cd ~/chimesh-mqtt
git pull origin main
bash deploy.sh

# Development
ssh ubuntu@3.141.31.229
cd ~/chimesh-mqtt
git pull origin dev
ENVIRONMENT=dev bash deploy.sh
```

### Wipe Dev Database
```bash
# Via GitHub Actions workflow dispatch
gh workflow run deploy.yml --repo emuehlstein/chimesh-mqtt \
  --ref dev -f environment=dev -f reset_db=true

# Or manually
ssh ubuntu@3.141.31.229
docker exec corescope-dev rm -f /app/data/meshcore.db
docker restart corescope-dev
```

### Backup Production Database
```bash
ssh ubuntu@13.58.181.117
docker exec corescope tar czf /tmp/backup.tar.gz /app/data/meshcore.db
docker cp corescope:/tmp/backup.tar.gz ~/corescope-backup-$(date +%Y%m%d).tar.gz
scp ubuntu@13.58.181.117:~/corescope-backup-*.tar.gz ~/backups/
```

### Add MQTT Authentication (Future)
Edit `mosquitto.conf` and mount it into the container.

## Firmware Fork: WS Custom Broker

A fork of MeshCore adds WebSocket + JWT auth support for custom brokers.

- **Fork:** [github.com/emuehlstein/MeshCore](https://github.com/emuehlstein/MeshCore) (from KMusorin/MeshCore)
- **Branch:** `feature/ws-custom-broker`
- **New CLI commands:** `set mqtt.ws on|off`, `set mqtt.tls on|off`
- **Pattern:** Same WSS+JWT auth as LetsMesh

### Pre-Built Binary (Heltec v3 Repeater/Observer)
```
https://chicagooffline-firmware.s3.us-east-2.amazonaws.com/meshcore/Heltec_v3_repeater_observer_mqtt-ws-custom-broker.bin
```
S3 bucket: `chicagooffline-firmware` (us-east-2)

See `OBSERVER_SETUP.md` for flash and configuration instructions.

## Troubleshooting

### Deploy Failures

**SSH timeout / broken pipe:**
- Cause: Long Docker builds (>5 min) on slow instances
- Fix: GitHub Actions workflow has `ServerAliveInterval=60` keepalive
- Solution: Use t3.small or larger (builds in ~3-4 min vs 8+ on t3.micro)

**DNS mismatch:**
- Symptom: HTTPS cert errors, wrong content served
- Cause: DNS records pointing to old IPs
- Fix: Update all A records to current instance IP, wait 60s (TTL)

**No packets in dev-scope:**
- Cause: `dev-config.json` broker URL was `mqtt://corescope:1883` (local container) instead of `mqtt://mqtt.chicagooffline.com:1883` (prod broker)
- Fix: Update `dev-config.json` → commit → redeploy

### Observer Node Issues
See `OBSERVER_SETUP.md` for detailed observer configuration.

## Cost Management

### Production (Always On)
- t3.small: ~$15/mo
- Route 53: ~$0.50/mo
- Data transfer: ~$1-5/mo
- **Total: ~$17-20/mo**

### Development (Stop When Not in Use)
- t3.small stopped: $0 compute, ~$1/mo for EBS storage
- t3.small running: ~$0.02/hr (~$15/mo if left on)
- **Recommended:** Stop dev instance when not actively testing

### Stop/Start Dev Instance
```bash
# Stop
aws ec2 stop-instances --region us-east-2 --instance-ids i-015964acf101b916d

# Start (IP may change, update DNS + GitHub secret)
aws ec2 start-instances --region us-east-2 --instance-ids i-015964acf101b916d
IP=$(aws ec2 describe-instances --region us-east-2 --instance-ids i-015964acf101b916d \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
echo "New IP: $IP"

# Update DNS + CI secret
aws route53 change-resource-record-sets --hosted-zone-id Z0192662J0UU9ADD406Z ...
gh secret set SSH_HOST --repo emuehlstein/chimesh-mqtt --env dev --body "$IP"
```

## Development Workflow

1. **Make changes** to CoreScope fork or config files
2. **Commit + push** to `dev` branch
3. **GitHub Actions** auto-deploys to dev-scope.chicagooffline.com
4. **Test** changes in browser
5. **Merge to `main`** when ready for production
6. **GitHub Actions** auto-deploys to scope.chicagooffline.com

## Instance Bootstrap (User-Data)

Fresh EC2 instances use this user-data script to pre-install Docker:

```bash
#!/bin/bash
while ! ping -c1 google.com &>/dev/null; do sleep 1; done
curl -fsSL https://get.docker.com | sh
usermod -aG docker ubuntu
systemctl stop unattended-upgrades
systemctl disable unattended-upgrades
```

This avoids the deploy script needing to install Docker mid-run (which was causing SSH session re-exec issues).
