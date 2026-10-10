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
