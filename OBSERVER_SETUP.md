# MeshCore Native Observer Setup

Guide for configuring MeshCore nodes running **observer-uplink-native-dev** firmware to publish to chicagooffline.com.

## Prerequisites

- MeshCore node flashed with `observer-uplink-native-dev` firmware
- Serial connection to the node (USB or UART)
- WiFi credentials for the node's network

## MQTT Configuration Commands

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
   # Should return: mqtt.chicagooffline.com
   ```

2. **Monitor serial output** for connection logs:
   ```
   [MQTT] Connecting to mqtt.chicagooffline.com:1883...
   [MQTT] Connected
   ```

3. **Check CoreScope web UI:**
   - Open https://scope.chicagooffline.com
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
