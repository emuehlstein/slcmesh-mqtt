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
const ed = require("@noble/ed25519");
const { sha512 } = require("@noble/hashes/sha512");

// noble/ed25519 v2: wire up sha512 so getPublicKey works synchronously
ed.etc.sha512Sync = (...m) => sha512(...m);

// ── JWT helpers ─────────────────────────────────────────────────────────────

const TOKEN_LIFETIME_S = 86400; // 1 day
const TOKEN_RENEW_FRACTION = 0.75; // renew after 75% of lifetime

function base64url(str) {
  return Buffer.from(str)
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=/g, "");
}

async function makeJwt(privKey, pubKeyHex, audience) {
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({ alg: "Ed25519", typ: "JWT" }));
  const payload = base64url(
    JSON.stringify({
      publicKey: pubKeyHex,
      aud: audience,
      iat: now,
      exp: now + TOKEN_LIFETIME_S,
      client: "observer-matrix",
    })
  );
  const signing = `${header}.${payload}`;
  const sig = await ed.sign(Buffer.from(signing, "utf8"), privKey);
  const sigHex = Buffer.from(sig).toString("hex").toUpperCase();
  return { token: `${signing}.${sigHex}`, expiresAt: now + TOKEN_LIFETIME_S };
}

// ── Config from environment ─────────────────────────────────────────────────

const PORT = parseInt(process.env.PORT || "3100", 10);
const STALE_THRESHOLD_MS = parseInt(
  process.env.STALE_THRESHOLD_MS || String(15 * 60 * 1000),
  10
); // 15 min

// MQTT sources as JSON array: [{name, label, broker, auth?, username?, password?, audience?, topics}]
const MQTT_SOURCES = JSON.parse(process.env.MQTT_SOURCES || "[]");

// ── State ───────────────────────────────────────────────────────────────────

// observers[pubkey] = { name, model, firmware, radio, lastSeen: { [sourceName]: timestamp } }
const observers = {};

// source connection status
const sourceStatus = {}; // sourceName -> { connected, lastError, reconnects, lastMessageTime }

const tokenTimers = {}; // sourceName -> Timer

// ── Startup ─────────────────────────────────────────────────────────────────

async function scheduleTokenRenewal(src, privKey, pubKeyHex, client) {
  const renewInMs = Math.floor(TOKEN_LIFETIME_S * TOKEN_RENEW_FRACTION * 1000);
  if (tokenTimers[src.name]) clearTimeout(tokenTimers[src.name]);
  const t = setTimeout(async () => {
    try {
      console.log(`[${src.name}] JWT renewing…`);
      const { token } = await makeJwt(privKey, pubKeyHex, src.audience);
      client.options.password = token;
      client.reconnect();
      await scheduleTokenRenewal(src, privKey, pubKeyHex, client);
    } catch (err) {
      console.error(`[${src.name}] JWT renewal error:`, err.message);
    }
  }, renewInMs);
  t.unref();
  tokenTimers[src.name] = t;
}

async function main() {
  // ── Keypair ───────────────────────────────────────────────────────────────
  let privKey, pubKeyHex;
  if (process.env.ED25519_PRIVATE_KEY_HEX && process.env.ED25519_PUBLIC_KEY_HEX) {
    privKey = Buffer.from(process.env.ED25519_PRIVATE_KEY_HEX, "hex");
    pubKeyHex = process.env.ED25519_PUBLIC_KEY_HEX.toUpperCase();
    console.log(`[jwt] Using keypair from env. Public key: ${pubKeyHex}`);
  } else {
    privKey = ed.utils.randomPrivateKey();
    const pubBytes = ed.getPublicKey(privKey); // sync with sha512Sync set
    pubKeyHex = Buffer.from(pubBytes).toString("hex").toUpperCase();
    console.log(`[jwt] Auto-generated keypair (ephemeral). To persist, set:`);
    console.log(`[jwt]   ED25519_PRIVATE_KEY_HEX=${Buffer.from(privKey).toString("hex")}`);
    console.log(`[jwt]   ED25519_PUBLIC_KEY_HEX=${pubKeyHex}`);
  }

  // ── MQTT subscriptions ────────────────────────────────────────────────────
  for (const src of MQTT_SOURCES) {
    sourceStatus[src.name] = {
      label: src.label || src.name,
      connected: false,
      lastError: null,
      reconnects: 0,
      lastMessageTime: null,
    };

    const opts = {
      clientId: `observer-matrix-${src.name}-${Date.now()}`,
      reconnectPeriod: 5000,
      connectTimeout: 10000,
    };

    if (src.auth === "jwt") {
      if (!src.audience) throw new Error(`[${src.name}] JWT auth requires 'audience'`);
      const { token } = await makeJwt(privKey, pubKeyHex, src.audience);
      opts.username = `v1_${pubKeyHex}`;
      opts.password = token;
    } else if (src.auth === "none") {
      // no credentials
    } else {
      // "userpass" or unspecified
      if (src.username) opts.username = src.username;
      if (src.password) opts.password = src.password;
    }

    const client = mqtt.connect(src.broker, opts);

    if (src.auth === "jwt") {
      await scheduleTokenRenewal(src, privKey, pubKeyHex, client);
    }

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
      // Track last message time for this source regardless of topic
      sourceStatus[src.name].lastMessageTime = Date.now();

      // Only process status heartbeats: meshcore/{region}/{pubkey}/status
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
      if (msg.origin) obs.name = msg.origin;
      if (msg.model) obs.model = msg.model;
      if (msg.firmware_version) obs.firmware = msg.firmware_version;
      if (msg.radio) obs.radio = msg.radio;
      obs.region = parts[1];
      obs.lastSeen[src.name] = Date.now();
      if (msg.stats) obs.stats = msg.stats;
    });
  }

  // ── HTTP server ───────────────────────────────────────────────────────────

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
        lastMessageTime: sourceStatus[s.name]?.lastMessageTime ?? null,
        lastMessageAgo: sourceStatus[s.name]?.lastMessageTime
          ? now - sourceStatus[s.name].lastMessageTime
          : null,
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
}

main().catch((err) => {
  console.error("Fatal startup error:", err);
  process.exit(1);
});
