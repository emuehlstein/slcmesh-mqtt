# chicagooffline.com - CoreScope Deployment

MeshCore network analyzer for Chicago (ORD region).

## URLs
- **Web UI:** https://chicagooffline.com
- **MQTT Broker:** mqtt://mqtt.chicagooffline.com:1883

## Architecture
```
chicagooffline.com (EC2 t3.small)
├── CoreScope Docker Container
│   ├── Mosquitto MQTT broker (port 1883)
│   ├── Go backend + packet store
│   ├── Caddy HTTPS proxy
│   └── Web UI
└── Data Sources
    ├── Local observer nodes → publish to mqtt.chicagooffline.com:1883
    └── (Optional) LetsMesh public feed
```

## Deployment

### Manual (Initial Setup)
SSH into EC2 and run:
```bash
cd ~/chicagooffline-corescope
bash deploy.sh
```

### Automated (GitHub Actions)
Push to `main` branch → auto-deploys via GitHub Actions.

**Required GitHub Secrets:**
- `SSH_PRIVATE_KEY` - Private key for EC2 access
- `SSH_HOST` - EC2 elastic IP
- `SSH_USER` - `ubuntu`

## Configuration

### config.json
CoreScope configuration. Edit and commit to trigger deployment.

### Caddyfile
Caddy reverse proxy + HTTPS. Handles:
- `chicagooffline.com` → CoreScope web UI
- `mqtt.chicagooffline.com` → MQTT documentation

### Connecting Observer Nodes
Point your observer nodes (meshcoretomqtt, meshcore-packet-capture) to:
```
mqtt://mqtt.chicagooffline.com:1883
topic: meshcore/ORD/<node-pubkey>/packets
```

## Monitoring
```bash
# View logs
docker logs -f corescope

# Check status
docker ps | grep corescope

# Restart
docker restart corescope
```

## DNS Records
```
A    chicagooffline.com       → <EC2-elastic-ip>
A    mqtt.chicagooffline.com  → <EC2-elastic-ip>
```

## Maintenance

### Update CoreScope
```bash
docker pull ghcr.io/kpa-clawbot/corescope:latest
bash deploy.sh
```

### Add MQTT Authentication (Future)
Edit mosquitto config and mount it into the container.

### Backup Database
```bash
docker exec corescope tar czf /tmp/backup.tar.gz /app/data/meshcore.db
docker cp corescope:/tmp/backup.tar.gz ~/corescope-backup-$(date +%Y%m%d).tar.gz
```
