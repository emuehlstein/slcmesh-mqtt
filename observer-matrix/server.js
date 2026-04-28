/**
 * Observer Status Matrix
 *
 * Subscribes to multiple MQTT environments, tracks observer /status heartbeats,
 * and serves a JSON API + static HTML dashboard.
 */

const http = require("http");
const fs = require("fs");
const path = require("path");
const mqtt = require("mqtt");

// ── Config from environment ─────────────────────────────────────────────────

const PORT = parseInt(process.env.PORT || "3100", 10);
const STALE_THRESHOLD_MS = parseInt(
  process.env.STALE_THRESHOLD_MS || String(15 * 60 * 1000),
  10
); // 15 min

// MQTT sources as JSON array: [{name, label, broker, username?, password?, topics}]
const MQTT_SOURCES = JSON.parse(process.env.MQTT_SOURCES || "[]");

// ── State ───────────────────────────────────────────────────────────────────

// observers[pubkey] = { name, model, firmware, radio, lastSeen: { [sourceName]: timestamp } }
const observers = {};

// source connection status
const sourceStatus = {}; // sourceName -> { connected, lastError, reconnects }

// ── MQTT subscriptions ──────────────────────────────────────────────────────

for (const src of MQTT_SOURCES) {
  sourceStatus[src.name] = {
    label: src.label || src.name,
    connected: false,
    lastError: null,
    reconnects: 0,
  };

  const opts = {
    clientId: `observer-matrix-${src.name}-${Date.now()}`,
    reconnectPeriod: 5000,
    connectTimeout: 10000,
  };
  if (src.username) opts.username = src.username;
  if (src.password) opts.password = src.password;

  const client = mqtt.connect(src.broker, opts);

  client.on("connect", () => {
    console.log(`[${src.name}] Connected to ${src.broker}`);
    sourceStatus[src.name].connected = true;
    sourceStatus[src.name].lastError = null;

    for (const topic of src.topics || ["meshcore/#"]) {
      client.subscribe(topic, (err) => {
        if (err) console.error(`[${src.name}] Subscribe error:`, err.message);
        else console.log(`[${src.name}] Subscribed: ${topic}`);
      });
    }
  });

  client.on("error", (err) => {
    console.error(`[${src.name}] Error:`, err.message);
    sourceStatus[src.name].lastError = err.message;
  });

  client.on("close", () => {
    sourceStatus[src.name].connected = false;
  });

  client.on("reconnect", () => {
    sourceStatus[src.name].reconnects++;
  });

  client.on("message", (topic, payload) => {
    // Only care about status messages: meshcore/{region}/{pubkey}/status
    const parts = topic.split("/");
    if (parts.length !== 4 || parts[0] !== "meshcore" || parts[3] !== "status")
      return;

    const pubkey = parts[2];
    let msg;
    try {
      msg = JSON.parse(payload.toString());
    } catch {
      return;
    }

    if (!observers[pubkey]) {
      observers[pubkey] = {
        name: msg.origin || "Unknown",
        model: msg.model || "",
        firmware: msg.firmware_version || "",
        radio: msg.radio || "",
        region: parts[1],
        lastSeen: {},
        stats: {},
      };
    }

    const obs = observers[pubkey];
    // Update metadata (may change over time)
    if (msg.origin) obs.name = msg.origin;
    if (msg.model) obs.model = msg.model;
    if (msg.firmware_version) obs.firmware = msg.firmware_version;
    if (msg.radio) obs.radio = msg.radio;
    obs.region = parts[1];

    // Track per-source last seen
    const now = Date.now();
    obs.lastSeen[src.name] = now;

    // Store latest stats
    if (msg.stats) obs.stats = msg.stats;
  });
}

// ── HTTP server ─────────────────────────────────────────────────────────────

const indexHtml = fs.readFileSync(
  path.join(__dirname, "public", "index.html"),
  "utf8"
);

const server = http.createServer((req, res) => {
  if (req.url === "/api/observers" || req.url === "/api/observers/") {
    const now = Date.now();
    const sourceNames = MQTT_SOURCES.map((s) => ({
      name: s.name,
      label: s.label || s.name,
      connected: sourceStatus[s.name]?.connected ?? false,
    }));

    const rows = Object.entries(observers)
      .map(([pubkey, obs]) => ({
        pubkey,
        pubkeyPrefix: pubkey.substring(0, 6),
        name: obs.name,
        model: obs.model,
        firmware: obs.firmware,
        radio: obs.radio,
        region: obs.region,
        stats: obs.stats,
        environments: Object.fromEntries(
          MQTT_SOURCES.map((s) => {
            const lastSeen = obs.lastSeen[s.name] || null;
            const isStale = lastSeen
              ? now - lastSeen > STALE_THRESHOLD_MS
              : true;
            return [
              s.name,
              {
                lastSeen,
                lastSeenAgo: lastSeen ? now - lastSeen : null,
                status: lastSeen ? (isStale ? "stale" : "online") : "unseen",
              },
            ];
          })
        ),
      }))
      .sort((a, b) => a.name.localeCompare(b.name));

    res.writeHead(200, {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
    });
    res.end(JSON.stringify({ sources: sourceNames, observers: rows }, null, 2));
    return;
  }

  // Serve index
  res.writeHead(200, { "Content-Type": "text/html" });
  res.end(indexHtml);
});

server.listen(PORT, () => {
  console.log(`Observer Matrix listening on :${PORT}`);
  console.log(
    `MQTT sources: ${MQTT_SOURCES.map((s) => s.label || s.name).join(", ") || "(none)"}`
  );
});
