const mqtt = require("mqtt");

const WS_URL = process.env.WS_BROKER_URL || "ws://meshcore-mqtt-broker:8883";
const WS_USER = process.env.WS_BROKER_USER || "";
const WS_PASS = process.env.WS_BROKER_PASS || "";
const TCP_URL = process.env.TCP_BROKER_URL || "mqtt://mosquitto:1883";
const TOPIC = process.env.BRIDGE_TOPIC || "meshcore/#";

console.log(`[bridge] WS source: ${WS_URL}`);
console.log(`[bridge] TCP target: ${TCP_URL}`);
console.log(`[bridge] topic: ${TOPIC}`);

let forwarded = 0;

const ws = mqtt.connect(WS_URL, {
  username: WS_USER || undefined,
  password: WS_PASS || undefined,
  clientId: `mqtt-bridge-${Date.now()}`,
  reconnectPeriod: 5000,
});

const tcp = mqtt.connect(TCP_URL, {
  clientId: `mqtt-bridge-pub-${Date.now()}`,
  reconnectPeriod: 5000,
});

ws.on("connect", () => {
  console.log("[bridge] connected to WS broker");
  ws.subscribe(TOPIC, { qos: 0 }, (err) => {
    if (err) console.error("[bridge] WS subscribe error:", err);
    else console.log(`[bridge] subscribed to ${TOPIC} on WS broker`);
  });
});

tcp.on("connect", () => {
  console.log("[bridge] connected to TCP mosquitto");
});

ws.on("message", (topic, payload) => {
  tcp.publish(topic, payload, { qos: 0, retain: false });
  forwarded++;
  if (forwarded % 100 === 1) {
    console.log(`[bridge] forwarded ${forwarded} messages (latest: ${topic})`);
  }
});

ws.on("error", (err) => console.error("[bridge] WS error:", err.message));
tcp.on("error", (err) => console.error("[bridge] TCP error:", err.message));
ws.on("close", () => console.log("[bridge] WS disconnected"));
tcp.on("close", () => console.log("[bridge] TCP disconnected"));

// Health log every 5 minutes
setInterval(() => {
  console.log(`[bridge] alive — ${forwarded} messages forwarded total`);
}, 300000);
