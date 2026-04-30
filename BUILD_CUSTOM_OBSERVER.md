# Build Salt Lake Cityland Observer Firmware

Guide for building MeshCore observer firmware from the `chioff-flex` branch with Salt Lake Cityland defaults baked in.

## Source Repository

```bash
git clone --branch chioff-flex https://github.com/emuehlstein/MeshCore.git
cd MeshCore
```

The `chioff-flex` branch is based on agessaman's `mqtt-bridge-implementation-flex` with Salt Lake Cityland-specific additions:
- `chioff` and `chioff-dev` MQTT presets (WSS + JWT auth to slcoffline.com)
- Salt Lake Cityland radio defaults (910.525 MHz / BW 62.5 / SF7 / CR5)
- 3-byte path hash and moderate loop detect defaults
- Board-specific MQTT slot configurations

## Build Targets

### Heltec V3 (Repeater + Observer)
```bash
pio run -e Heltec_v3_repeater_observer_mqtt
```

### Heltec V4 (Repeater + Observer)
```bash
pio run -e Heltec_v4_repeater_observer_mqtt
```

### Station G2 (Repeater + Observer)
```bash
pio run -e Station_G2_repeater_observer_mqtt
```

### T-Beam SX1262 (Repeater + Observer)
```bash
pio run -e TBeam_SX1262_repeater_observer_mqtt
```

### T-Beam S3 Supreme (Repeater + Observer)
```bash
pio run -e TBeam_S3_Supreme_repeater_observer_mqtt
```

### LilyGo T3S3 (Repeater + Observer)
```bash
pio run -e T3S3_repeater_observer_mqtt
```

### Heltec Wireless Tracker (Repeater only, no MQTT)
```bash
pio run -e Wireless_Tracker_repeater
```
Note: The Wireless Tracker build requires MQTT file exclusions in `src_filter` (already configured in the `chioff-flex` branch).

## Flash

### Via USB (esptool)
```bash
pio run -e <target> -t upload
```

### Clean Flash (Erase First)
Recommended when switching from a different firmware or to reset all saved preferences:
```bash
pio run -e <target> -t erase
pio run -e <target> -t upload
```

## What's Baked In at Compile Time

### Radio Defaults (platformio.ini)
```ini
-D LORA_FREQ=910.525
-D LORA_BW=62.5
-D LORA_SF=7
```
CR defaults to 5 (MeshCore standard).

### Path Hash & Loop Detect (CommonCLI.cpp)
```ini
-D DEFAULT_PATH_HASH_MODE=2     # 3-byte hashes
-D DEFAULT_LOOP_DETECT=2        # moderate
```
These only apply on fresh flash (no saved preferences file). Existing nodes with saved prefs are unaffected.

### MQTT Preset Defaults (CommonCLI.cpp)

**V3/V4 builds** (no PSRAM, 2 active slots max):
- Slot 0: `chimesh` (chimesh.org WSS)
- Slot 1: `chioff` (slcoffline.com WSS)

**G2 builds** (PSRAM, 5 active slots):
- Slot 0: `analyzer-us` (LetsMesh US)
- Slot 1: `chimesh` (chimesh.org WSS)
- Slot 2: `chioff` (slcoffline.com WSS)
- Slot 3: `chioff-dev` (slcoffline.com dev WSS) — enabled via `-D CHIOFF_DEFAULT_SLOT3`

### MQTT RX/TX Defaults
- `mqtt.rx`: ON (publishes RF-received packets to MQTT)
- `mqtt.tx`: OFF (does NOT re-publish own transmitted packets — avoids duplicates)

## Available MQTT Presets (MQTTPresets.h)

| ID | Name | Broker URL |
|----|------|-----------|
| 0 | `none` | — (disable slot) |
| 1 | `chimesh` | wss://mqtt.chimesh.org |
| 2 | `chioff` | wss://wsmqtt.slcoffline.com:443/mqtt |
| 3 | `chioff-dev` | wss://wsmqtt-dev.slcoffline.com:443/mqtt |
| 4 | `analyzer-us` | LetsMesh US |
| 5 | `analyzer-eu` | LetsMesh EU |
| 6 | `letsmesh` | LetsMesh (legacy) |

All WSS presets use JWT auth via Ed25519 device keys (username: `v1_{PUBKEY}`).

## Board PSRAM Matrix

| Board | PSRAM | Max Active TLS Slots | Default Slots |
|-------|-------|---------------------|---------------|
| Heltec V3 | ❌ | 2 | chimesh, chioff |
| Heltec V4 | ✅ | 5 | chimesh, chioff |
| Station G2 | ✅ | 5 | analyzer-us, chimesh, chioff, chioff-dev |
| T-Beam SX1262 | ✅ | 5 | chimesh, chioff |
| T-Beam S3 Supreme | ❌ | 2 | chimesh, chioff |
| LilyGo T3S3 | ✅ | 5 | chimesh, chioff |

PSRAM detection: `psramFound() ? 5 : 2` max active slots. Each TLS/WSS connection needs ~40KB of mbedTLS buffers.

## Customization

### Add a New MQTT Preset

1. Edit `src/helpers/MQTTPresets.h` — add entry to `MQTTPresetConfig presets[]`
2. Update `NUM_MQTT_PRESETS` count
3. Rebuild all targets

### Change Default Slots for a Board

Edit the board's `platformio.ini` env:
```ini
build_flags =
    -D DEFAULT_MQTT_SLOT0_PRESET=1    ; chimesh
    -D DEFAULT_MQTT_SLOT1_PRESET=2    ; chioff
```

### Enable chioff-dev Default on Additional Boards

Add to the board's `platformio.ini`:
```ini
build_flags =
    -D CHIOFF_DEFAULT_SLOT3
```

## Post-Flash Configuration

After flashing, connect via serial (115200 baud):

```bash
# Required
set wifi.ssid <SSID>
set wifi.pwd <password>
set mqtt.email <email>
set mqtt.iata SLC
set name <NodeName>
set lat <latitude>
set lon <longitude>
reboot
```

See [OBSERVER_SETUP.md](OBSERVER_SETUP.md) for full configuration guide.

## Release Process

1. Build all board targets
2. Collect `.bin` files from `.pio/build/<env>/firmware.bin`
3. Create GitHub release on [emuehlstein/MeshCore](https://github.com/emuehlstein/MeshCore)
4. Upload binaries named `<Board>_repeater_observer_mqtt.bin`

Current release: [Latest](https://github.com/emuehlstein/MeshCore/releases/latest)

## Related Documentation

- [OBSERVER_SETUP.md](OBSERVER_SETUP.md) — Post-flash configuration guide
- [emuehlstein/MeshCore](https://github.com/emuehlstein/MeshCore) — Source (branch: `chioff-flex`)
- [agessaman/MeshCore](https://github.com/agessaman/MeshCore) — Upstream MQTT flex branch
