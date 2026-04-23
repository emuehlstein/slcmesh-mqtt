# MeshCore Native Observer Setup

Guide for configuring MeshCore nodes running **observer-uplink-native-dev** firmware to publish to chicagooffline.com.

Two connection methods are supported — choose based on your firmware and target environment.

## Prerequisites

- MeshCore node flashed with `observer-uplink-native-dev` firmware (Method 1) or `feature/ws-custom-broker` firmware (Method 2)
- Serial connection to the node (USB or UART)
- WiFi credentials for the node's network

## Method 1: Plain TCP (Production)

The standard setup — no auth, any firmware, connects to the production MQTT broker.

Connect to the node via serial (115200 baud) and run:

```bash
# Set MQTT broker
set mqtt.server mqtt.chicagooffline.com

# Set MQTT port (if needed, default is likely 1883)
set mqtt.port 1883

# Set region/topic prefix (ORD = Chicago)
set mqtt.topic meshcore/ORD

# Save and reboot
reboot
```

## Method 2: WebSocket + JWT (Dev)

Connects to the dev environment's `meshcore-mqtt-broker` via WSS with JWT authentication.
Requires the `feature/ws-custom-broker` firmware fork.

### Firmware Fork

- **Repo:** [github.com/emuehlstein/MeshCore](https://github.com/emuehlstein/MeshCore) (fork of KMusorin/MeshCore)
- **Branch:** `feature/ws-custom-broker`
- **New commands:** `set mqtt.ws on|off`, `set mqtt.tls on|off`

### Pre-Built Binary (Heltec v3)

Download and flash without building:
```
https://chicagooffline-firmware.s3.us-east-2.amazonaws.com/meshcore/Heltec_v3_repeater_observer_mqtt-ws-custom-broker.bin
```

Flash via serial (esptool or OTA):
```bash
# Via esptool (USB)
esptool.py --chip esp32s3 --port /dev/ttyUSB0 write_flash 0x0 \
  Heltec_v3_repeater_observer_mqtt-ws-custom-broker.bin

# Or via OTA from existing firmware
start ota
# (follow prompts to provide binary URL)
```

### Serial Configuration for WS Broker

Connect via serial (115200 baud) and run:

```bash
# Set MQTT broker hostname
set mqtt.server wsmqtt-dev.chicagooffline.com

# Set MQTT port (WSS default is 443; use 443 or whatever the broker exposes)
set mqtt.port 443

# Enable WebSocket transport
set mqtt.ws on

# Enable TLS (required for WSS)
set mqtt.tls on

# Set region/topic prefix (ORD = Chicago)
set mqtt.topic meshcore/ORD

# Save and reboot
reboot
```

Auth is handled automatically via Ed25519 device keys (JWT). The firmware generates `v1_{PUBKEY}` as the MQTT username.

### mctomqtt (Bridge Mode)

`mctomqtt` (meshcoretomqtt) supports both TCP and WebSocket methods. For WS mode, configure the broker URL as:
```
wss://wsmqtt-dev.chicagooffline.com/mqtt
```
No firmware changes needed — the bridge handles the WS connection on behalf of the node.

## WiFi Configuration

The node needs WiFi to reach the MQTT broker. Commands vary by firmware, but typically:

```bash
# Set WiFi SSID
set wifi.ssid YourNetworkName

# Set WiFi password
set wifi.password YourPassword

# Enable WiFi
set wifi.enabled on

# Save and reboot
reboot
```

## Multiple MQTT Servers

**Not supported natively.** Each node can only publish to one MQTT broker at a time. 

To send data to multiple destinations:
- Run multiple observer nodes
- Use MQTT bridge/relay on the server side

## Verification

After configuring and rebooting:

1. **Check MQTT connection status:**
   ```bash
   get mqtt.server
   # Method 1: mqtt.chicagooffline.com
   # Method 2: wsmqtt-dev.chicagooffline.com
   ```

2. **Monitor serial output** for connection logs:
   ```
   # Method 1 (TCP)
   [MQTT] Connecting to mqtt.chicagooffline.com:1883...
   [MQTT] Connected

   # Method 2 (WSS)
   [MQTT] Connecting to wss://wsmqtt-dev.chicagooffline.com/mqtt...
   [MQTT] Connected
   ```

3. **Check CoreScope web UI:**
   - Method 1: https://scope.chicagooffline.com
   - Method 2: https://dev-scope.chicagooffline.com
   - Look for your node's packets appearing in the feed

## Troubleshooting

### MQTT not connecting
- Verify WiFi is connected: `get wifi.status`
- Check DNS resolution: `ping mqtt.chicagooffline.com`
- Confirm firewall allows outbound port 1883

### Packets not appearing in CoreScope
- Verify topic format: `meshcore/ORD/<node-pubkey>/packets`
- Check node's public key: `get public.key`
- Monitor MQTT broker logs: `ssh ubuntu@13.58.181.117 'docker logs -f corescope | grep MQTT'`

### Commands not recognized
- Ensure firmware is `observer-uplink-native-dev` (not standard repeater firmware)
- Check firmware version: `ver`
- Update firmware if needed: `start ota`

## Example Full Setup

```bash
# Connect via serial (115200 baud)

# Configure WiFi
set wifi.ssid MyHomeNetwork
set wifi.password MySecurePassword123
set wifi.enabled on

# Configure MQTT
set mqtt.server mqtt.chicagooffline.com
set mqtt.port 1883
set mqtt.topic meshcore/ORD

# Set node name and location (optional)
set name ChicagoObserver1
set lat 41.8781
set lon -87.6298

# Save and reboot
reboot
```

## Related Documentation

- [CoreScope README](README.md) — Deployment and monitoring
- [MeshCore CLI Commands](https://docs.meshcore.io/cli_commands/) — Full command reference
- [LetsMesh Onboarding](https://analyzer.letsmesh.net/observer/onboard) — Observer registration
- [emuehlstein/MeshCore](https://github.com/emuehlstein/MeshCore) — WS custom broker firmware fork
- [chicagooffline-firmware S3 bucket](https://chicagooffline-firmware.s3.us-east-2.amazonaws.com/) — Pre-built binaries (us-east-2)
