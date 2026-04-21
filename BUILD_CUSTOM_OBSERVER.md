# Build Custom Observer Firmware with chicagooffline.com

Guide for building MeshCore observer firmware with hardcoded MQTT server.

## Source Repository

**Adam Gessaman's MQTT Bridge PR:**
```bash
git clone --branch mqtt-bridge-implementation https://github.com/agessaman/MeshCore.git
cd MeshCore
```

## Configuration

### 1. WiFi Credentials (Required)

Edit the example code to add WiFi credentials. The firmware will auto-connect on boot.

Create `variants/station_g2/wifi_config.h`:
```cpp
#ifndef WIFI_CONFIG_H
#define WIFI_CONFIG_H

#define WIFI_SSID "YourNetworkName"
#define WIFI_PASSWORD "YourPassword"

#endif
```

### 2. MQTT Broker Configuration

The MQTTBridge supports **3 concurrent brokers** (`MAX_MQTT_BROKERS=3`):
- Broker 0: Custom (your chicagooffline.com server)
- Broker 1: LetsMesh US (optional)
- Broker 2: LetsMesh EU (optional)

**Option A: Hardcode in Source**

Edit `src/helpers/bridges/MQTTBridge.cpp` and modify `setBrokerDefaults()`:

```cpp
void MQTTBridge::setBrokerDefaults() {
  // Broker 0: Custom chicagooffline.com server
  setBroker(0, "mqtt.chicagooffline.com", 1883, "", "", true);
  
  // Broker 1: LetsMesh US (disable if not needed)
  setBroker(1, "mqtt-us-v1.letsmesh.net", 443, "", "", false);
  
  // Broker 2: LetsMesh EU (disable if not needed)
  setBroker(2, "mqtt-eu-v1.letsmesh.net", 443, "", "", false);
}
```

**Option B: Configure via CLI After Flash**

Leave defaults as-is and configure after flashing:
```bash
set mqtt.broker.0.host mqtt.chicagooffline.com
set mqtt.broker.0.port 1883
set mqtt.broker.0.enabled on
reboot
```

### 3. IATA Code (Region)

Set your region code (used in MQTT topic):
```cpp
// In platformio.ini, add:
-D MQTT_IATA='"ORD"'
```

Or configure after flash:
```bash
set mqtt.iata ORD
```

## Build Targets

### Station G2 with MQTT Bridge

**Target:** `env:Station_G2_repeater_bridge_mqtt`

**Build command:**
```bash
pio run -e Station_G2_repeater_bridge_mqtt
```

**Flash command:**
```bash
pio run -e Station_G2_repeater_bridge_mqtt -t upload
```

### Heltec V3 with MQTT Bridge

Check `variants/heltec_v3/platformio.ini` for MQTT bridge targets.

## Build Flags Reference

Key flags in `platformio.ini`:
```ini
-D WITH_MQTT_BRIDGE=1          # Enable MQTT bridge
-D MAX_MQTT_BROKERS=3          # Support 3 concurrent brokers
-D MQTT_MAX_PACKET_SIZE=1024   # Max packet size
-D MQTT_DEBUG=1                # Enable debug logging
-D CONFIG_MBEDTLS_CERTIFICATE_BUNDLE=y  # SSL/TLS support
```

## CLI Commands Reference

After flashing custom firmware with MQTT bridge enabled:

### WiFi Commands
```bash
get wifi.ssid
get wifi.status
set wifi.ssid <network>
set wifi.password <password>
set wifi.enabled on
```

### MQTT Commands
```bash
get mqtt.status               # Show all broker status
get mqtt.server              # Get broker 0 hostname
set mqtt.server <hostname>   # Set broker 0 hostname
set mqtt.port <port>         # Set broker 0 port
get mqtt.iata                # Get region code
set mqtt.iata <code>         # Set region code (e.g., ORD)
set mqtt.broker.0.enabled on # Enable custom broker
set mqtt.broker.1.enabled off # Disable LetsMesh US
set mqtt.broker.2.enabled off # Disable LetsMesh EU
```

### Message Types
```bash
set mqtt.msgs on             # Enable packet publishing
set mqtt.status on           # Enable status messages
set mqtt.raw on              # Enable raw packet data
```

## MQTT Topic Structure

Published topics follow this pattern:
```
meshcore/{IATA}/{PUBKEY}/packets
meshcore/{IATA}/{PUBKEY}/status
meshcore/{IATA}/{PUBKEY}/raw
```

Example for Chicago (ORD):
```
meshcore/ORD/ABC123/packets
meshcore/ORD/ABC123/status
meshcore/ORD/ABC123/raw
```

## Verification

After flashing and configuring:

1. **Check WiFi connection:**
   ```bash
   get wifi.status
   # Should show: connected
   ```

2. **Check MQTT status:**
   ```bash
   get mqtt.status
   # Should show: broker: connected
   ```

3. **Monitor MQTT feed locally:**
   ```bash
   mosquitto_sub -h mqtt.chicagooffline.com -p 1883 -t 'meshcore/#' -v
   ```

4. **Check CoreScope UI:**
   - Open https://scope.chicagooffline.com
   - Look for your node's packets in the feed

## Troubleshooting

### WiFi not connecting
- Verify SSID and password are correct
- Check 2.4GHz WiFi is available (5GHz not supported)
- Serial debug should show WiFi connection attempts

### MQTT broker disconnected
- Verify WiFi is connected first
- Check DNS resolution: `ping mqtt.chicagooffline.com`
- Verify broker is running: `curl -I https://mqtt.chicagooffline.com`
- Check firewall allows outbound port 1883

### No packets in CoreScope
- Verify MQTT is connected: `get mqtt.status`
- Check topic format matches: `meshcore/ORD/<pubkey>/packets`
- Monitor raw MQTT feed to confirm publishing
- Check LoRa radio is receiving packets: `neighbors`

## Alternative: Use meshcoretomqtt Instead

If you don't want to build custom firmware, use the **meshcoretomqtt** Python bridge instead:
- Connects to any MeshCore repeater via serial/USB
- Publishes packets to your MQTT broker
- Easier to configure, no firmware changes needed
- Repo: https://github.com/Cisien/meshcoretomqtt

## Related Files

- Source: `src/helpers/bridges/MQTTBridge.cpp`
- Header: `src/helpers/bridges/MQTTBridge.h`
- Example: `examples/simple_repeater` (with `-D WITH_MQTT_BRIDGE=1`)
- Config: `variants/station_g2/platformio.ini`
