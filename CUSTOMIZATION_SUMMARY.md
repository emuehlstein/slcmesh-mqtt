# Salt Lake City Customization Summary

**Repository:** https://github.com/emuehlstein/slcmesh-mqtt.git  
**Base:** emuehlstein/chimesh-mqtt (Chicago Offline)  
**Completed:** 2026-04-30

## What Was Changed

### 1. **Domains & Infrastructure**
| Item | Chicago | Salt Lake City |
|------|---------|----------------|
| Primary domain | chicagooffline.com | slcoffline.com |
| Shorthand domain | chioff.com | slcoff.com |
| Region code | ORD | SLC |
| Docker network | chicagooffline-net | slcoffline-net |
| Map center | 41.8781, -87.6298 | 40.7608, -111.8910 |
| Map zoom | 11 | 11 (unchanged) |

### 2. **Branding & Colors**
| Element | Chicago | Salt Lake City |
|---------|---------|----------------|
| Site name | Chicago Offline | Salt Lake Offline |
| Tagline | off-grid comms for Chicago | off-grid comms for Salt Lake City |
| Primary accent | #00E5FF (Signal Cyan) | #4FC3F7 (Wasatch Blue) |
| Alert/CTA | #FFB300 (Beacon Amber) | #FF7043 (Sunset Coral) |
| Status green | #39FF14 (Mesh Green) | #8BC34A (Sage Green) |
| Background | #0C0F1A | #0A0E18 |
| Surface | #141829 | #121728 |
| Text primary | #EDF2FF | #E8EAF6 |
| Text secondary | #A0AABF | #90A4AE |

**Inspiration:** Wasatch Mountains (Utah) + desert sunset palette

### 3. **Configuration Files Updated**
- ✅ `config.json` — map center, IATA, branding, themeDark colors
- ✅ `dev-config.json` — same as above
- ✅ `Caddyfile` — all domain references
- ✅ `Caddyfile.dev` — all domain references
- ✅ `docker-compose.prod.yml` — network name, CoreScope fork path
- ✅ `docker-compose.dev.yml` — network name, CoreScope fork path
- ✅ `.github/workflows/deploy.yml` — repo reference (slcmesh-mqtt)
- ✅ `deploy-compose.sh` — CoreScope fork, MQTT broker audience, branding
- ✅ `meshcore-mqtt-broker/.env.example` — audience reference
- ✅ `README.md` — completely rewritten for SLC

### 4. **Landing Pages & Documentation**
- ✅ `landing/index.html` — title, description, meta tags, colors, content
- ✅ `dev-landing/index.html` — same
- ✅ `landing/*.html` — all branding references
- ✅ `dev-landing/*.html` — all branding references
- ✅ `OBSERVER_SETUP.md` — region-specific instructions, rewritten
- ✅ `BUILD_CUSTOM_OBSERVER.md` — updated references
- ✅ `PLAN-*.md` — updated references
- ✅ `docs/architecture.md` — updated references

### 5. **Preconfigured Mesh Configs**
- ✅ Renamed `00-chicagoland.env` → `00-slcland.env`
- ✅ Renamed `00-chicagoland.toml` → `00-slcland.toml`
- ✅ Updated all script references (`install-observer.sh`, etc.)
- ✅ Updated HTML documentation (contributors.html, setup.html)

### 6. **Scripts & Deploy Tools**
- ✅ `deploy-compose.sh` — SLC-specific environment names, broker audience, MQTT brokers
- ✅ `deploy-broker.sh` — audience references
- ✅ `scripts/install-observer.sh` — config file references
- ✅ `dev-landing/install-observer.sh` — config file references

## What Was NOT Changed (Upstream Dependencies)

✅ **Kept as-is — external dependencies:**
- CoreScope fork reference → `emuehlstein/CoreScope-slcoffline` (separate repo)
- health-check → `emuehlstein/meshcore-health-check` (external)
- live-map → `yellowcooln/meshcore-mqtt-live-map` (external)
- web-keygen → `agessaman/meshcore-web-keygen` (external)
- mqtt-broker → `michaelhart/meshcore-mqtt-broker` (external)
- MeshCore firmware MQTT presets (analyzer-us, chimesh, etc.) — firmware-level, not our domain

✅ **Kept as-is — shared MQTT topics:**
- Topic structure: `meshcore/SLC/<node-pubkey>/packets` (updated region code only)
- Channel keys (generic, can be reused)
- MQTT preset names (firmware-defined)

## Git History

```
9d4099c Rename preconfigured mesh configs: 00-chicagoland → 00-slcland
37df797 Initial Salt Lake City customization of chimesh-mqtt
```

### Branch Structure
| Branch | Purpose | Deploys to |
|--------|---------|-----------|
| `main` | Source of truth, all changes | **dev EC2 on push** |
| `slc-dev` | Development tracking | dev EC2 (manual or via workflow) |
| `slc-prod` | Production tracking | prod EC2 (manual or via workflow) |

**Promotion workflow:**
```bash
# Develop on main
git push origin main  # → triggers dev deploy

# When ready for production:
git checkout slc-prod
git merge main
git push origin slc-prod  # → triggers production deploy
```

## Deployment Checklist

Before deploying to production, ensure:

1. **GitHub Secrets (per environment)** are configured:
   - `SSH_PRIVATE_KEY` — EC2 SSH key
   - `SSH_HOST` — EC2 IP address
   - `SSH_USER` — ubuntu (or custom)
   - `DEPLOY_KEY` — ed25519 key for git clone
   - `CARTOGRAPHER_HEALTHCHECK_KEY` — health check channel secret
   - `BROKER_CORESCOPE_PASSWORD` — MQTT broker password
   - `BROKER_ADMIN_PASSWORD` — MQTT admin password
   - `CHIMESH_VIEWER_PASSWORD` — ChiMesh.org viewer credentials
   - `BROKER_REMOTE_CORESCOPE_PASSWORD` — remote broker password (if bridging)

2. **DNS Records** (Route 53) point to correct EC2 IPs:
   - Production: `slcoffline.com`, `scope.slcoffline.com`, etc. → prod EC2
   - Development: `dev-scope.slcoffline.com`, etc. → dev EC2
   - Tile server: `tiles.slcoffline.com` → tile server EC2

3. **CoreScope-slcoffline** fork exists and is accessible:
   - Repo: `emuehlstein/CoreScope-slcoffline`
   - Branch: `deploy/slcoffline`

4. **Local `.env` file** (if testing locally):
   - Copy `.env.example` → `.env`
   - Fill in real passwords before `docker compose up`

## Files Summary

### Configuration (JSON)
- `config.json` — production CoreScope config
- `dev-config.json` — development CoreScope config
- `dev-theme.json` — development UI theme overrides

### Docker & Deployment
- `docker-compose.prod.yml` — production stack
- `docker-compose.dev.yml` — development stack
- `.env.example` — example secrets template
- `.env.broker` — generated per deploy
- `.env.healthcheck` — generated per deploy
- `.env.livemap` — generated per deploy
- `.env.observer-matrix` — generated per deploy

### Web
- `Caddyfile` — production TLS routing
- `Caddyfile.dev` — development TLS routing
- `landing/` — production landing page + assets
- `dev-landing/` — development landing page + assets
- `keygen/` — meshcore-web-keygen (bundled, static)

### Documentation
- `README.md` — architecture, deployment, tools
- `OBSERVER_SETUP.md` — observer configuration guide
- `BUILD_CUSTOM_OBSERVER.md` — custom observer build
- `OBSERVER_SETUP.md` — observer quick-start
- `PLAN-*.md` — internal planning docs (reference only)

### Scripts
- `deploy-compose.sh` — main deployment script (EC2)
- `deploy-broker.sh` — MQTT broker bootstrap (EC2)
- `scripts/install-observer.sh` — observer setup script
- `dev-landing/install-observer.sh` — observer setup (dev)

## Next Steps for Deployment

1. **Create CoreScope-slcoffline fork:**
   - Fork emuehlstein/CoreScope (or pull from upstream)
   - Create `deploy/slcoffline` branch
   - Update CoreScope's config to use SLC colors + map

2. **Set up AWS infrastructure:**
   - EC2 instances (prod, dev, tile server)
   - Route 53 hosted zone + DNS records
   - Security groups + IAM roles

3. **Configure GitHub Secrets:**
   - Set environment-specific secrets for prod/dev

4. **Test deployment:**
   ```bash
   # Local test (if Docker available)
   docker compose -f docker-compose.dev.yml up -d
   # Check http://localhost (if Caddy configured for 127.0.0.1)
   ```

5. **Deploy to dev EC2:**
   ```bash
   git push origin main  # triggers dev deploy via GitHub Actions
   ```

6. **Promote to production:**
   ```bash
   git checkout slc-prod
   git merge main
   git push origin slc-prod  # triggers prod deploy
   ```

## Customization Reference

**To further customize for SLC:**
- Update `landing/index.html` with local community content
- Add SLC-specific mesh nodes/contacts to documentation
- Customize `keygen/` with SLC-themed instructions
- Add SLC-specific map layers to `tiles.slcoffline.com`

**To adapt for another region:**
- Repeat this process with region-specific domains, colors, coordinates
- Update CoreScope fork path
- Verify upstream repos are compatible

---

**Questions?** See README.md for architecture overview, or OBSERVER_SETUP.md for observer-specific guidance.
