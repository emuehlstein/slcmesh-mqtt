# slcoffline.com Architecture

## System Overview

```mermaid
graph TB
    subgraph "Internet"
        DNS[Route 53<br/>Z0192662J0UU9ADD406Z]
        Users[Users/Browsers]
        MeshNodes[Mesh Nodes<br/>Observers/Repeaters]
    end

    subgraph "GitHub"
        MainBranch[main branch]
        ProdBranch[prod branch]
        GHA[GitHub Actions<br/>deploy.yml]
    end

    subgraph "PROD EC2<br/>13.58.181.117<br/>i-03e3d22e2d0ecf096"
        subgraph "Docker Network: slcoffline-net"
            Caddy[Caddy<br/>:80/:443<br/>TLS + Reverse Proxy]
            CoreScope[CoreScope<br/>:3000<br/>Packet Analyzer]
            HealthCheck[meshcore-health-check<br/>:3090]
            MQTTBroker[meshcore-mqtt-broker<br/>:8883<br/>WebSocket + JWT]
            Mosquitto[Mosquitto<br/>:1883<br/>Plain TCP]
            LiveMap[meshmap-live<br/>Live MQTT Map]
            ObsMatrix[observer-matrix<br/>Observer Dashboard]
        end
        Landing[Static Landing<br/>/srv/landing]
        DevLanding[Dev Landing<br/>/srv/dev-landing]
        Keygen[Keygen<br/>/srv/keygen]
    end

    subgraph "DEV EC2<br/>3.141.31.229<br/>i-015964acf101b916d"
        subgraph "Docker Network: slcoffline-net (dev)"
            CaddyDev[Caddy<br/>:80/:443<br/>TLS + Reverse Proxy]
            CoreScopeDev[CoreScope<br/>:3000]
            HealthCheckDev[meshcore-health-check<br/>:3090]
            MQTTBrokerDev[meshcore-mqtt-broker<br/>:8883]
            MosquittoDev[Mosquitto<br/>:1883]
            LiveMapDev[meshmap-live]
            ObsMatrixDev[observer-matrix]
        end
        LandingDev[Dev Landing<br/>/srv/dev-landing]
        KeygenDev[Keygen<br/>/srv/keygen]
    end

    subgraph "MAP EC2<br/>3.20.103.82<br/>i-000c894fdc2b38cf1"
        TileServer[Tile Server<br/>tiles.slcoffline.com]
    end

    %% DNS routing
    DNS -->|slcoffline.com<br/>*.slcoffline.com| Caddy
    DNS -->|dev-*.slcoffline.com| CaddyDev
    DNS -->|tiles.slcoffline.com| TileServer

    %% Users
    Users --> DNS

    %% Mesh nodes
    MeshNodes -->|MQTT TCP :1883| Mosquitto
    MeshNodes -->|WebSocket MQTT :443| MQTTBroker
    MeshNodes -->|WebSocket MQTT :443| MQTTBrokerDev

    %% Caddy routing (prod)
    Caddy -->|scope.slcoffline.com| CoreScope
    Caddy -->|health.slcoffline.com<br/>healthcheck.slcoffline.com| HealthCheck
    Caddy -->|wsmqtt.slcoffline.com<br/>ws.slcoff.com| MQTTBroker
    Caddy -->|livemap.slcoffline.com| LiveMap
    Caddy -->|keygen.slcoffline.com| Keygen
    Caddy -->|slcoffline.com| Landing
    Caddy -->|dev-landing.slcoffline.com| DevLanding

    %% Caddy routing (dev)
    CaddyDev -->|dev-scope.slcoffline.com| CoreScopeDev
    CaddyDev -->|dev-health.slcoffline.com| HealthCheckDev
    CaddyDev -->|wsmqtt-dev.slcoffline.com| MQTTBrokerDev
    CaddyDev -->|dev-livemap.slcoffline.com| LiveMapDev
    CaddyDev -->|dev-keygen.slcoffline.com| KeygenDev
    CaddyDev -->|dev-landing.slcoffline.com| LandingDev

    %% Internal MQTT connections
    Mosquitto -.->|Internal| CoreScope
    MQTTBroker -.->|Internal| CoreScope
    MosquittoDev -.->|Internal| CoreScopeDev
    MQTTBrokerDev -.->|Internal| CoreScopeDev

    %% CI/CD
    MainBranch -->|push| GHA
    ProdBranch -->|push| GHA
    GHA -->|SSH deploy| CaddyDev
    GHA -->|SSH deploy| Caddy

    style Caddy fill:#4FC3F7,color:#000
    style CaddyDev fill:#4FC3F7,color:#000
    style MQTTBroker fill:#8BC34A,color:#000
    style MQTTBrokerDev fill:#8BC34A,color:#000
    style CoreScope fill:#FF7043,color:#000
    style CoreScopeDev fill:#FF7043,color:#000
```

## Key Components

### Production (13.58.181.117)
- **Caddy:** TLS termination, reverse proxy, serves static sites
- **CoreScope:** Packet analyzer web UI (port 3000, internal)
- **meshcore-mqtt-broker:** WebSocket MQTT with JWT auth (port 8883, proxied)
- **Mosquitto:** Plain TCP MQTT (port 1883, no auth, for CoreScope + dev testing)
- **meshcore-health-check:** Mesh health dashboard (port 3090, internal)
- **meshmap-live:** Live MQTT node map
- **observer-matrix:** Observer status dashboard

### Development (3.141.31.229)
- Same stack as prod, `dev-*` subdomains
- Used for pre-production testing

### Map Server (3.20.103.82)
- **tiles.slcoffline.com:** Tile server for map rendering

### DNS (Route 53: Z0192662J0UU9ADD406Z)
- Wildcard `*.slcoffline.com` → prod
- Explicit `dev-*` records → dev
- `tiles.slcoffline.com` → map server

### CI/CD
- `main` branch → auto-deploy to dev
- `prod` branch → auto-deploy to production
- GitHub Actions uses SSH to deploy Docker Compose stacks

## Mesh Observer Config

Observers/nodes connect to MQTT brokers in priority order:
1. LetsMesh US (mqtt-us-v1.letsmesh.net:443, WebSocket, JWT token auth)
2. ChiMesh.org (mqtt.chimesh.org:443, WebSocket, JWT token auth)
3. Salt Lake Offline prod (wsmqtt.slcoffline.com:443, WebSocket, JWT token auth)
4. Salt Lake Offline dev (wsmqtt-dev.slcoffline.com:443, WebSocket, JWT token auth)
5. rflab.io (mqtt.rflab.io:443, WebSocket, JWT token auth)
6. LetsMesh EU (mqtt-eu-v1.letsmesh.net:443, WebSocket, JWT token auth)
7. Salt Lake Offline TCP fallback (mqtt.slcoff.com:1883, plain TCP, no auth, no TLS)
