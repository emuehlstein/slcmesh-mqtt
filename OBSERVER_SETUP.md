# MeshCore Chicagoland Observer Setup

Guide for configuring MeshCore nodes as observers for the Chicago Mesh network.

## Quick Start: Chicagoland Firmware (Recommended)

Flash the **Chicagoland observer firmware** from [emuehlstein/MeshCore](https://github.com/emuehlstein/MeshCore) (`chioff-flex` branch). Pre-built binaries are available in the [v0.4.1-chicagoland release](https://github.com/emuehlstein/MeshCore/releases/tag/v0.4.1-chicagoland).

### What's Baked In (No Commands Needed)

- **Radio:** 910.525 MHz / BW 62.5 / SF7 / CR5 (Chicagoland standard)
- **Path hash mode:** 2 (3-byte)
- **Loop detect:** moderate
- **MQTT presets (V3/V4/WSL3):** analyzer-us (slot 0) + chimesh (slot 1) + chioff (slot 2)
- **MQTT presets (G2):** chimesh + chioff + analyzer-us + analyzer-eu + chioff-dev (5 active slots)
- **mqtt.rx:** on (publishes RF-received packets to MQTT)
- **mqtt.tx:** off (does NOT re-publish own transmitted packets)

### Post-Flash Configuration

Connect via serial (115200 baud) and run:

```bash
# Required — WiFi and LetsMesh auth
set wifi.ssid <SSID>
set wifi.pwd <password>
set mqtt.email <your-email>      # For LetsMesh JWT auth
set mqtt.iata ORD                # Chicago region code

# Required — node identity and location
set name <YourNodeName>
set lat <latitude>
set lon <longitude>

# Apply changes
reboot
```

### Optional Configuration

```bash
# Restore a private key (to keep the same identity after re-flash)
set prv.key <64-byte-hex>

# Set TX power (default varies by board)
set txpower 22

# Enable repeating (off by default for pure observers)
set repeat on

# Change MQTT preset slots (if needed)
set mqtt1.preset chimesh
set mqtt2.preset chioff
set mqtt3.preset analyzer-us
```

### Available MQTT Presets

| Preset | Broker | Notes |
|--------|--------|-------|
| `chimesh` | wss://mqtt.chimesh.org | Community broker |
| `chioff` | wss://wsmqtt.chicagooffline.com | Chicago Offline (prod) |
| `chioff-dev` | wss://wsmqtt-dev.chicagooffline.com | Chicago Offline (dev) |
| `analyzer-us` | LetsMesh US | Default on G2 |
| `analyzer-eu` | LetsMesh EU | European broker |
| `letsmesh` | LetsMesh (legacy) | Older LetsMesh endpoint |
| `none` | — | Disable slot |

### Board PSRAM & Slot Limits

| Board | PSRAM | Max Active MQTT Slots | Default Slots |
|-------|-------|-----------------------|---------------|
| Heltec V3 | ❌ | 2 | analyzer-us, chimesh, chioff |
| Heltec V4 | ✅ | 5 | analyzer-us, chimesh, chioff |
| Heltec WSL3 | ✅ | 5 | analyzer-us, chimesh, chioff |
| Heltec V4 Expansion Kit | ✅ | 5 | analyzer-us, chimesh, chioff |
| Station G2 | ✅ | 5 | chimesh, chioff, analyzer-us, analyzer-eu, chioff-dev |
| T-Beam SX1262 | ✅ | 5 | analyzer-us, chimesh, chioff |
| T-Beam S3 Supreme | ❌ | 2 | analyzer-us, chimesh, chioff |
| LilyGo T3S3 | ✅ | 5 | analyzer-us, chimesh, chioff |

Boards without PSRAM (V3, T-Beam Supreme) can configure 3 MQTT slots but only 2 will be active simultaneously — each TLS connection needs ~40KB of mbedTLS buffers. Station G2 is the only board with `chioff-dev` as a default slot.

## Quick Config Tool: Web Serial (Recommended for First-Time Setup)

Use the **MeshCore Web Serial Config Tool** to configure a freshly-flashed node without typing serial commands manually:

- **URL:** <https://chicago-offline.github.io/meshcore-config/>
- **Works in:** Chrome or Edge (Web Serial API required — not supported in Firefox/Safari)
- **Features:** Set node name, lat/lon (with browser geolocation), WiFi credentials, MQTT IATA, repeat toggle, advert intervals, admin password
- **Includes:** Serial log viewer showing all commands sent/received

Connect via USB, open the tool, click **Connect**, and fill in the fields. The tool sends serial commands automatically.

## Alternative: Plain TCP (Any Firmware)

If you're running standard MeshCore firmware without the Chicagoland presets:

```bash
set mqtt.server mqtt.chicagooffline.com
set mqtt.port 1883
set mqtt.iata ORD
reboot
```

No authentication required. Works with any MQTT-enabled firmware or `mctomqtt` bridge.

## Alternative: Pi Bridge (meshcore-packet-capture / mctomqtt)

Run our installer to set up packet capture with all Chicagoland MQTT brokers pre-configured. Supports companions, repeaters, and room servers:

```bash
bash <(curl -fsSL https://chicagooffline.com/install-observer.sh)
```

The installer detects your node type and runs the appropriate upstream tool:
- [meshcore-packet-capture](https://github.com/agessaman/meshcore-packet-capture) for companions
- [mctomqtt](https://github.com/Cisien/meshcoretomqtt) for repeaters/room servers

Pre-configured with 6 brokers: LetsMesh US & EU, chimesh.org, rflab.io, Chicago Offline (prod + dev).

### Config Only (Existing Installs)

**Companions** (`.env` format):
```bash
curl -O https://chicagooffline.com/00-chicagoland.env
cp 00-chicagoland.env ~/.meshcore-packet-capture/.env.local
```

**Repeaters / Room Servers** (TOML format):
```bash
curl -O https://chicagooffline.com/00-chicagoland.toml
sudo cp 00-chicagoland.toml /etc/mctomqtt/config.d/
```

## Verification

After configuring and rebooting:

1. **Check WiFi:**
   ```bash
   get wifi
   # Should show: connected, IP address, RSSI
   ```

2. **Check MQTT status:**
   ```bash
   get mqtt.status
   # Should show: connected for active slots
   ```

3. **Check neighbors:**
   ```bash
   neighbors
   # Lists nearby nodes and signal strengths
   ```

4. **Check CoreScope:**
   - Production: https://scope.chicagooffline.com
   - Dev: https://dev-scope.chicagooffline.com
   - Look for your node's packets in the feed

## MQTT Naming Reference

| Setting | Meaning | Observer Default |
|---------|---------|-----------------|
| `mqtt.rx` | RF packets received → publish to MQTT | ON ✅ |
| `mqtt.tx` | RF packets transmitted/repeated → publish to MQTT | OFF ✅ |
| `mqtt.status` | Node status/telemetry → publish to MQTT | ON ✅ |
| `mqtt.packets` | Packet metadata → publish to MQTT | ON ✅ |

**Important:** `mqtt.tx` should be OFF for observers. Enabling it causes duplicate packets on the broker (the node re-publishes its own repeated packets).

## Troubleshooting

### WiFi not connecting
- Verify SSID and password: `get wifi`
- Check for "4-way handshake timeout" — usually wrong password
- Ensure 2.4GHz WiFi is available (5GHz not supported by ESP32)

### MQTT slot shows "inactive"
- Board doesn't have enough PSRAM for all configured slots
- V3 boards: max 2 active slots. Prioritize chimesh + chioff
- Reconfigure: `set mqtt1.preset chimesh` → `set mqtt2.preset chioff`

### MQTT shows "disconnected"
- WiFi must be connected first
- Check `get mqtt.status` — queue count shows buffered messages
- Wait 30-60 seconds after reboot for TLS handshake

### Packets not appearing in CoreScope
- Verify `mqtt.rx` is on: `get mqtt.rx`
- Check your radio parameters match the network (910.525/62.5/SF7/CR5 for Chicago)
- Verify region code: `get mqtt.iata` should show `ORD`

## Related Documentation

- [BUILD_CUSTOM_OBSERVER.md](BUILD_CUSTOM_OBSERVER.md) — Building firmware from source
- [emuehlstein/MeshCore](https://github.com/emuehlstein/MeshCore) — Chicagoland firmware fork (branch: `chioff-flex`)
- [v0.4.1-chicagoland release](https://github.com/emuehlstein/MeshCore/releases/tag/v0.4.1-chicagoland) — Pre-built binaries (properly merged, all boards)
- [Chicago-Offline/meshcore-config](https://github.com/Chicago-Offline/meshcore-config) — Web Serial config tool
- [MeshCore CLI Commands](https://docs.meshcore.io/cli_commands/) — Full command reference
