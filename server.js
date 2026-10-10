const express = require("express");
const cors = require("cors");
const { AccessToken, RoomServiceClient } = require("livekit-server-sdk");

const app = express();
app.use(cors());
app.use(express.json());

// Registro seguro de solicitudes para diagnosticar la conexión del iPhone.
// No imprime tokens, API keys ni secretos.
app.use((req, _res, next) => {
  console.log(`[request] ${req.method} ${req.path}`);
  next();
});

app.get("/", (_req, res) => {
  res.json({ service: "DIVISA SHOPPER LiveKit token service", status: "ok" });
});

app.get("/health", (_req, res) => res.json({ ok: true }));


// Diagnóstico temporal: comprueba desde Render la conexión autenticada
// con LiveKit. Nunca devuelve ni registra credenciales o tokens.
app.get("/health/livekit", async (_req, res) => {
  try {
    const url = process.env.LIVEKIT_URL;
    const key = process.env.LIVEKIT_API_KEY;
    const secret = process.env.LIVEKIT_API_SECRET;
    if (!url || !key || !secret) {
      return res.status(503).json({ ok: false, stage: "configuration" });
    }
    const endpoint = new URL(url);
    endpoint.protocol = endpoint.protocol === "wss:" ? "https:" : "http:";
    const service = new RoomServiceClient(endpoint.origin, key, secret);
    await service.listRooms();
    console.log("[livekit-check] authenticated room API succeeded");
    return res.json({ ok: true, stage: "livekit-authenticated" });
  } catch (error) {
    const message = String(error?.message || error);
    const code = Number(error?.status || error?.statusCode || 0);
    console.error("[livekit-check] failed", code || "unknown", message.slice(0, 180));
    return res.status(502).json({
      ok: false,
      stage: "livekit-authenticated",
      status: code || null,
      error: message.slice(0, 180)
    });
  }
});


// Diagnóstico temporal de señalización WebSocket (sin revelar el token).
// El código 101 indica que LiveKit aceptó el protocolo WebSocket.
app.get("/health/livekit/signal", async (_req, res) => {
  const url = process.env.LIVEKIT_URL;
  const key = process.env.LIVEKIT_API_KEY;
  const secret = process.env.LIVEKIT_API_SECRET;
  if (!url || !key || !secret) {
    return res.status(503).json({ ok: false, stage: "configuration" });
  }
  try {
    const token = new AccessToken(key, secret, {
      identity: "server-signal-diagnostic",
      name: "Connection Diagnostic",
      ttl: "5m"
    });
    token.addGrant({ roomJoin: true, room: "divisa-shopper-prueba" });
    const jwt = await token.toJwt();
    const target = new URL(url);
    target.protocol = target.protocol === "https:" ? "wss:" : target.protocol;
    target.pathname = "/rtc";
    target.searchParams.set("access_token", jwt);
    target.searchParams.set("protocol", "15");
    target.searchParams.set("auto_subscribe", "0");

    // Node 22+ built-in WebSocket. On success, LiveKit sends a join response.
    if (typeof WebSocket !== "function") {
      return res.status(503).json({ ok: false, stage: "websocket-unavailable" });
    }
    const result = await new Promise((resolve) => {
      const ws = new WebSocket(target.toString());
      let settled = false;
      const finish = (data) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        try { ws.close(); } catch {}
        resolve(data);
      };
      const timer = setTimeout(() => finish({ ok: false, stage: "signal-timeout" }), 8000);
      ws.addEventListener("open", () => finish({ ok: true, stage: "signal-open" }));
      ws.addEventListener("error", (event) => finish({
        ok: false,
        stage: "signal-error",
        message: String(event.message || "WebSocket connection rejected").slice(0, 160)
      }));
      ws.addEventListener("close", (event) => finish({
        ok: false, stage: "signal-closed", code: event.code
      }));
    });
    console.log("[signal-check]", result.stage);
    res.status(result.ok ? 200 : 502).json(result);
  } catch (error) {
    console.error("[signal-check] exception", error?.name);
    res.status(502).json({ ok: false, stage: "signal-exception", type: error?.name || "Error" });
  }
});

app.post("/token", async (req, res) => {
  try {
    const apiKey = process.env.LIVEKIT_API_KEY;
    const apiSecret = process.env.LIVEKIT_API_SECRET;
    const url = process.env.LIVEKIT_URL;

    if (!apiKey || !apiSecret || !url) {
      return res.status(500).json({ error: "LiveKit environment variables are not configured" });
    }

    const room = String(req.body?.room || "").trim();
    const identity = String(req.body?.identity || "").trim();
    const name = String(req.body?.name || identity).trim();

    if (!room || !identity) {
      return res.status(400).json({ error: "room and identity are required" });
    }

    const token = new AccessToken(apiKey, apiSecret, { identity, name });
    token.addGrant({ roomJoin: true, room });
    const jwt = await token.toJwt();

    console.log(`[token] issued room=${room} identity=${identity} livekitHost=${safeHost(url)}`);
    res.json({ token: jwt, url });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: "Could not create token" });
  }
});

function safeHost(value) {
  try {
    return new URL(value).host;
  } catch {
    return "invalid-livekit-url";
  }
}

const port = Number(process.env.PORT || 3000);
app.listen(port, "0.0.0.0", () => {
  console.log(`DIVISA SHOPPER token service listening on port ${port}`);
});
