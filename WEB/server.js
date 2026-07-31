// server.js
//
// Backend for the LMArena Bridge Telegram Mini App.
// Node/Express port of contend_BRIDGE_main.py's dashboard routes, with the
// original password-form login replaced by Telegram initData verification
// (see telegramAuth.js). This is the piece that must run on a server that
// holds BOT_TOKEN — it can never ship to the browser bundle (App.js).
//
// Endpoints (all JSON in/out unless noted):
//   POST /api/auth/verify     { initData }              -> { user }            (sets session cookie)
//   POST /api/auth/logout                                -> { ok: true }
//   GET  /api/state           [auth]                     -> full dashboard state
//   POST /api/keys            [auth] { name, rpm }        -> created key
//   DELETE /api/keys/:key                        [auth]   -> { ok: true }
//   POST /api/tokens          [auth] { token }            -> { ok: true }
//   DELETE /api/tokens/:index [auth]                      -> { ok: true }
//   POST /api/refresh         [auth]                      -> refreshed state (stub: wire to real arena fetch)

require("dotenv").config();
const express = require("express");
const cookieParser = require("cookie-parser");
const cors = require("cors");
const jwt = require("jsonwebtoken");
const crypto = require("crypto");

const { verifyTelegramInitData } = require("./telegramAuth");
const { readConfig, writeConfig } = require("./store");

const {
  BOT_TOKEN,
  SESSION_JWT_SECRET,
  SESSION_TTL_HOURS = "24",
  INITDATA_MAX_AGE_HOURS = "24",
  CORS_ORIGINS = "*",
  PORT = "8787",
} = process.env;

if (!BOT_TOKEN || !SESSION_JWT_SECRET) {
  console.error(
    "FATAL: BOT_TOKEN and SESSION_JWT_SECRET must be set (see .env.example). Refusing to start."
  );
  process.exit(1);
}

const app = express();
app.use(express.json());
app.use(cookieParser());
app.use(
  cors({
    origin: CORS_ORIGINS === "*" ? true : CORS_ORIGINS.split(",").map((s) => s.trim()),
    credentials: true,
  })
);

const SESSION_COOKIE = "session";

/* ---------------------------------------------------------------------- */
/* Auth                                                                    */
/* ---------------------------------------------------------------------- */

app.post("/api/auth/verify", (req, res) => {
  const start = Date.now();
  const { initData } = req.body || {};
  const result = verifyTelegramInitData(initData, BOT_TOKEN, Number(INITDATA_MAX_AGE_HOURS));

  if (!result.valid) {
    try { require('fs').appendFileSync('/tmp/auth_times.log', `POST /api/auth/verify ${new Date().toISOString()} failed ${result.reason} (${Date.now()-start}ms)\n`); } catch(e){}
    return res.status(401).json({ ok: false, reason: result.reason });
  }

  // If ADMIN_ID is set, only allow that Telegram user id to get a session
  const ADMIN_ID = process.env.ADMIN_ID ? Number(process.env.ADMIN_ID) : null;
  if (ADMIN_ID && Number(result.user.id) !== ADMIN_ID) {
    try { require('fs').appendFileSync('/tmp/auth_times.log', `POST /api/auth/verify ${new Date().toISOString()} forbidden (${Date.now()-start}ms)\n`); } catch(e){}
    return res.status(403).json({ ok: false, reason: 'forbidden' });
  }

  const token = jwt.sign(
    { uid: result.user.id, user: result.user },
    SESSION_JWT_SECRET,
    { expiresIn: `${SESSION_TTL_HOURS}h` }
  );

  res.cookie(SESSION_COOKIE, token, {
    httpOnly: true,
    secure: true,
    sameSite: "none",
    maxAge: Number(SESSION_TTL_HOURS) * 60 * 60 * 1000,
  });

  try { require('fs').appendFileSync('/tmp/auth_times.log', `POST /api/auth/verify ${new Date().toISOString()} ok (${Date.now()-start}ms)\n`); } catch(e){}
  return res.json({ ok: true, user: result.user });
});

app.post("/api/auth/logout", (req, res) => {
  res.clearCookie(SESSION_COOKIE);
  res.json({ ok: true });
});

function requireAuth(req, res, next) {
  const token = req.cookies?.[SESSION_COOKIE];
  if (!token) return res.status(401).json({ ok: false, reason: "no_session" });
  try {
    req.session = jwt.verify(token, SESSION_JWT_SECRET);
    next();
  } catch {
    return res.status(401).json({ ok: false, reason: "invalid_session" });
  }
}

/* ---------------------------------------------------------------------- */
/* Dashboard state (mirrors config.json from the Python version)          */
/* ---------------------------------------------------------------------- */

function toDashboardState(config) {
  const hasAuthToken =
    Boolean(String(config.auth_token || "").trim()) || (config.auth_tokens || []).length > 0;
  return {
    api_keys: config.api_keys,
    auth_tokens: config.auth_tokens,
    has_auth_token: hasAuthToken,
    cf_clearance_configured: Boolean(config.cf_clearance),
    models: config.models,
    usage: config.usage,
    total_requests: Object.values(config.usage || {}).reduce((a, b) => a + b, 0),
  };
}

app.use(express.static(__dirname));

app.get("/", (req, res) => {
  res.sendFile(require('path').join(__dirname, 'index.html'));
});

// Client-side error reporting for diagnostics
app.post('/client-error', express.json(), (req, res) => {
  try {
    const data = req.body || {};
    console.error('[CLIENT ERROR]', JSON.stringify(data));
    const fs = require('fs');
    fs.appendFileSync('/tmp/client_errors.log', new Date().toISOString() + ' ' + JSON.stringify(data) + '\n');
  } catch (e) {
    console.error('Failed to write client error:', e);
  }
  res.json({ ok: true });
});

app.get("/api/state", requireAuth, (req, res) => {
  res.json(toDashboardState(readConfig()));
});

/* ---------------------------------------------------------------------- */
/* API keys — mirrors /create-key, /delete-key                            */
/* ---------------------------------------------------------------------- */

// Instrumented key creation: allow auto-generation when name is empty (frontend can request quick keys)
app.post("/api/keys", requireAuth, (req, res) => {
  const start = Date.now();
  const { name, rpm } = req.body || {};
  let cleanName = String(name || "").trim();
  if (!cleanName) {
    cleanName = `Auto key ${new Date().toISOString().replace(/[:.]/g, '-')}`;
  }

  const config = readConfig();
  const newKey = {
    name: cleanName,
    key: `sk-lmab-${crypto.randomUUID()}`,
    rpm: Math.max(1, Math.min(Number(rpm) || 60, 1000)),
    created: new Date().toISOString(),
  };
  config.api_keys.push(newKey);
  writeConfig(config);
  const elapsed = Date.now() - start;
  try { require('fs').appendFileSync('/tmp/auth_times.log', `POST /api/keys ${new Date().toISOString()} ${elapsed}ms\n`); } catch(e){}
  res.status(201).json({ ok: true, key: newKey });
});

app.delete("/api/keys/:key", requireAuth, (req, res) => {
  const config = readConfig();
  config.api_keys = config.api_keys.filter((k) => k.key !== req.params.key);
  writeConfig(config);
  res.json({ ok: true });
});

/* ---------------------------------------------------------------------- */
/* Arena auth tokens — mirrors /add-auth-token, /delete-auth-token        */
/* ---------------------------------------------------------------------- */

app.post("/api/tokens", requireAuth, (req, res) => {
  /*
   Accepts several formats in `token`:
    - plain string token
    - JSON string representing an array of cookies (from browser cookie export)
    - an Array of cookie objects [{ name, value, ... }]
    - an object map { "arena-auth-prod-v1.0": "...", "arena-auth-prod-v1.1": "..." }

   Merging policy (best-effort): prefer v1.0 if present (strip leading "base64-"), otherwise use v1.1. If an array is provided, pick the matching cookie objects.
  */
  try {
    let tokenInput = req.body?.token;
    if (!tokenInput) return res.status(400).json({ ok: false, reason: "token_required" });

    // If client sent a JSON string, try parse it.
    if (typeof tokenInput === "string") {
      const trimmed = tokenInput.trim();
      if ((trimmed.startsWith("[") || trimmed.startsWith("{"))) {
        try { tokenInput = JSON.parse(trimmed); } catch (e) { /* leave as string */ }
      }
    }

    let candidate = "";

    function pickFromArray(arr) {
      if (!Array.isArray(arr)) return "";
      const v10 = arr.find((c) => c && c.name && c.name.includes("arena-auth-prod-v1.0"));
      const v11 = arr.find((c) => c && c.name && c.name.includes("arena-auth-prod-v1.1"));
      if (v10 && v10.value) {
        return String(v10.value).replace(/^base64-/, "");
      }
      if (v11 && v11.value) {
        return String(v11.value);
      }
      // fallback: any cookie whose name starts with arena-auth
      const any = arr.find((c) => c && typeof c.name === 'string' && c.name.startsWith('arena-auth'));
      return any ? String(any.value) : "";
    }

    if (Array.isArray(tokenInput)) {
      candidate = pickFromArray(tokenInput);
    } else if (typeof tokenInput === 'object') {
      // object map
      if (tokenInput['arena-auth-prod-v1.0']) candidate = String(tokenInput['arena-auth-prod-v1.0']).replace(/^base64-/, '');
      else if (tokenInput['arena-auth-prod-v1.1']) candidate = String(tokenInput['arena-auth-prod-v1.1']);
      else if (Array.isArray(tokenInput.cookies)) candidate = pickFromArray(tokenInput.cookies);
      else candidate = '';
    } else if (typeof tokenInput === 'string') {
      candidate = tokenInput.trim();
    }

    candidate = String(candidate || "").trim();
    if (!candidate) return res.status(400).json({ ok: false, reason: 'no_token_found' });

    const config = readConfig();
    if (!config.auth_tokens.includes(candidate)) config.auth_tokens.push(candidate);
    writeConfig(config);
    return res.status(201).json({ ok: true, token: candidate });
  } catch (e) {
    console.error('Failed to process /api/tokens', e);
    return res.status(500).json({ ok: false, reason: 'server_error' });
  }
});

app.delete("/api/tokens/:index", requireAuth, (req, res) => {
  const idx = Number(req.params.index);
  const config = readConfig();
  if (idx >= 0 && idx < config.auth_tokens.length) {
    config.auth_tokens.splice(idx, 1);
    writeConfig(config);
  }
  res.json({ ok: true });
});

/* ---------------------------------------------------------------------- */
/* Refresh — calls Python bridge's /refresh-tokens endpoint                */
/* ---------------------------------------------------------------------- */

app.post("/api/refresh", requireAuth, async (req, res) => {
  try {
    // Fetch models from Python bridge
    let models = [];
    try {
      const modelsRes = await fetch("http://localhost:8000/api/v1/models", {
        signal: AbortSignal.timeout(10000),
      });
      if (modelsRes.ok) {
        const modelsData = await modelsRes.json();
        if (modelsData && modelsData.data) {
          models = modelsData.data.map((m, i) => ({
            name: m.id || m.name || `model-${i}`,
            rank: i + 1,
            org: m.owned_by || "unknown",
            capabilities: m.capabilities || [],
          }));
        }
      }
    } catch (e) {
      console.error("Failed to fetch models from bridge:", e.message);
    }

    // Call the Python bridge's refresh endpoint for tokens
    let authTokens = [];
    try {
      const bridgeRes = await fetch("http://localhost:8000/refresh-tokens", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        signal: AbortSignal.timeout(30000),
      });
      
      if (bridgeRes.ok) {
        const bridgeData = await bridgeRes.json();
        if (bridgeData && bridgeData.auth_tokens) {
          authTokens = bridgeData.auth_tokens;
        }
      }
    } catch (e) {
      console.error("Bridge refresh failed:", e.message);
    }

    // Update local config
    const config = readConfig();
    if (models.length > 0) config.models = models;
    if (authTokens.length > 0) config.auth_tokens = authTokens;
    writeConfig(config);

    res.json({ ok: true, state: toDashboardState(config) });
  } catch (e) {
    console.error("Refresh error:", e.message);
    const config = readConfig();
    res.json({ ok: true, state: toDashboardState(config) });
  }
});

app.listen(Number(PORT), async () => {
  console.log(`LMArena Bridge TG backend listening on :${PORT}`);
  
  // Auto-fetch models from Python bridge on startup
  try {
    const config = readConfig();
    if (!config.models || config.models.length === 0) {
      console.log("Fetching models from Python bridge...");
      const modelsRes = await fetch("http://localhost:8000/api/v1/models", {
        signal: AbortSignal.timeout(10000),
      });
      if (modelsRes.ok) {
        const modelsData = await modelsRes.json();
        if (modelsData && modelsData.data) {
          config.models = modelsData.data.map((m, i) => ({
            name: m.id || m.name || `model-${i}`,
            rank: i + 1,
            org: m.owned_by || "unknown",
            capabilities: m.capabilities || [],
          }));
          writeConfig(config);
          console.log(`Loaded ${config.models.length} models from bridge`);
        }
      }
    }
  } catch (e) {
    console.error("Failed to auto-fetch models:", e.message);
  }
});
