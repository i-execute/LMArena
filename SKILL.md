# SKILL: LMArena Bridge — Telegram Mini App migration

## What this is

`contend_BRIDGE_main.py` was a FastAPI dashboard for **LMArena Bridge** (a
proxy that turns lmarena.ai chat into an OpenAI-compatible API). It used a
plain password login (`admin` cookie session) and server-rendered HTML to
manage:

- API keys (name, generated `sk-lmab-...` key, RPM limit, created date)
- Arena auth tokens (round-robin list of `arena-auth-prod-v1...` strings)
- `cf_clearance` status (Cloudflare cookie, auto-refreshed)
- Available models (fetched from arena, ranked)
- Usage stats (request count per model)

This migration replaces:

- **Password login** → **Telegram Mini App login** (`initData` signature
  check against `BOT_TOKEN`)
- **Server-rendered HTML + forms** → **React SPA** (`App.js`) talking to a
  **JSON API** (`server.js`)

The bot token and session-signing secret never reach the browser. Only the
Node server (`/server`) holds them.

## Architecture

```
┌─────────────┐   initData (signed   ┌──────────────────┐   HMAC verify   ┌────────────┐
│  Telegram    │──by Telegram, not───▶│  App.js (React)   │────POST────────▶│ server.js  │
│  client      │   by you)            │  browser bundle    │  /api/auth/    │  (Node)    │
└─────────────┘                       └──────────────────┘   verify        └─────┬──────┘
                                                ▲                                  │ holds BOT_TOKEN,
                                       session cookie (httpOnly)                   │ SESSION_JWT_SECRET
                                                └──────────────────────────────────┘
                                                     all /api/* calls,
                                                     credentials: "include"
```

- `App.js` — self-contained React bundle (no imports/exports; global `App`
  function, per the WebDeployer convention already in the file). Renders the
  access gate, then the dashboard once a session cookie is set.
- `server.js` + `telegramAuth.js` + `store.js` — Node/Express backend. This
  is the piece that "должен хранится на сервере для проверки подписи через
  токен" (must live server-side to verify the signature via the bot token).

## The verification algorithm (do not skip steps)

Telegram signs `initData` with a key derived from your bot token. Verifying
it server-side is the *only* way to trust `user.id` from a Mini App:

1. Parse `initData` as a query string. Pull out `hash`; keep everything else
   (`user`, `auth_date`, `query_id`, ...).
2. Build the "data check string": sort the remaining `key=value` pairs
   alphabetically by key, join with `\n`.
3. `secret_key = HMAC_SHA256(key="WebAppData", data=<bot_token>)`
4. `computed_hash = HMAC_SHA256(key=secret_key, data=<data_check_string>)`,
   hex-encoded.
5. Constant-time compare `computed_hash` to the `hash` field. Reject on any
   mismatch.
6. Reject if `auth_date` is older than your replay window (default 24h
   here — `INITDATA_MAX_AGE_HOURS`).
7. Only after all of the above passes, trust `user` from `initData` and
   issue your own session (here: a JWT in an httpOnly cookie).

Reference implementation: `server/telegramAuth.js` (`verifyTelegramInitData`).
Full working example (including generating a *valid* initData string to test
against) is in the "Examples" section below.

## Endpoint reference

All `/api/*` routes except `/api/auth/verify` require the session cookie
(sent automatically by `fetch(..., { credentials: "include" })`).

| Method | Path                  | Body                    | Returns                          | Python equivalent          |
|--------|-----------------------|--------------------------|-----------------------------------|-----------------------------|
| POST   | `/api/auth/verify`    | `{ initData }`           | `{ ok, user }` + sets cookie      | `POST /login`               |
| POST   | `/api/auth/logout`    | —                        | `{ ok }`, clears cookie           | `GET /logout`                |
| GET    | `/api/state`          | —                        | full dashboard state (see below)  | `GET /dashboard` (render)    |
| POST   | `/api/keys`           | `{ name, rpm }`          | `{ ok, key }`                     | `POST /create-key`           |
| DELETE | `/api/keys/:key`      | —                        | `{ ok }`                          | `POST /delete-key`           |
| POST   | `/api/tokens`         | `{ token }`              | `{ ok }`                          | `POST /add-auth-token`       |
| DELETE | `/api/tokens/:index`  | —                        | `{ ok }`                          | `POST /delete-auth-token`    |
| POST   | `/api/refresh`        | —                        | `{ ok, state }`                   | `POST /refresh-tokens`       |

`GET /api/state` shape:

```json
{
  "api_keys": [{ "name": "Production Key", "key": "sk-lmab-...", "rpm": 60, "created": "2026-07-30T12:00:00.000Z" }],
  "auth_tokens": ["arena-auth-prod-v1...."],
  "has_auth_token": true,
  "cf_clearance_configured": true,
  "models": [{ "publicName": "claude-mythos-5", "rank": 1, "organization": "Anthropic" }],
  "usage": { "claude-mythos-5": 182 },
  "total_requests": 182
}
```

## Migration checklist (for the next model/dev picking this up)

- [ ] Set `BOT_TOKEN` (from @BotFather) and a random `SESSION_JWT_SECRET`
      (`openssl rand -hex 32`) in `server/.env` — copy from `.env.example`.
- [ ] Deploy `server/` somewhere with a stable HTTPS URL (Fly.io, Render,
      a VPS behind nginx, etc.) — anywhere that isn't the static frontend
      host, since it needs a real Node runtime and a secret env var.
- [ ] In `App.js`, set `API_BASE_URL` to that deployed URL (currently `"/api"`,
      i.e. same-origin — change this constant only, everything else derives
      from it).
- [ ] Point `CORS_ORIGINS` in `.env` at the frontend's deployed origin(s).
- [ ] Port `get_initial_data()` from the Python bridge into
      `POST /api/refresh` in `server.js` (currently a stub) — that's the
      piece that actually re-fetches `cf_clearance` + the model list from
      lmarena.ai.
- [ ] Swap `store.js`'s JSON file for a real database once you have more
      than one server instance (file-based state doesn't survive horizontal
      scaling or ephemeral filesystems).
- [ ] Register the Mini App URL with @BotFather (`/newapp` or `/setmenubutton`)
      so `tg.initData` is actually populated — a plain browser tab opened by
      URL has no `initData`, which is why `AccessGate` shows
      "not opened through the bot" in that case (this is expected, not a bug).

## Examples

### 1. Generating a valid `initData` for local testing

```js
const crypto = require("crypto");

function fakeInitData(botToken, user) {
  const authDate = Math.floor(Date.now() / 1000);
  const params = new URLSearchParams({
    auth_date: String(authDate),
    query_id: "AAH_test_query_id",
    user: JSON.stringify(user),
  });
  const dataCheckString = [...params.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([k, v]) => `${k}=${v}`)
    .join("\n");
  const secretKey = crypto.createHmac("sha256", "WebAppData").update(botToken).digest();
  const hash = crypto.createHmac("sha256", secretKey).update(dataCheckString).digest("hex");
  params.set("hash", hash);
  return params.toString();
}

// fakeInitData(process.env.BOT_TOKEN, { id: 12345, first_name: "Dev" })
```

Use this to curl `/api/auth/verify` without a real Telegram client:

```bash
INIT_DATA=$(node -e 'console.log(require("./gen")(process.env.BOT_TOKEN, {id:1,first_name:"Dev"}))')
curl -i -c cookies.txt -X POST http://localhost:8787/api/auth/verify \
  -H "Content-Type: application/json" \
  -d "{\"initData\": \"$INIT_DATA\"}"

curl -b cookies.txt http://localhost:8787/api/state
```

### 2. Calling the API from the frontend (already wired in `App.js`)

```js
// after a successful /api/auth/verify, the httpOnly cookie is set —
// every subsequent call just needs credentials: "include":
const state = await fetch("/api/state", { credentials: "include" }).then(r => r.json());

await fetch("/api/keys", {
  method: "POST",
  credentials: "include",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ name: "Production key", rpm: 60 }),
});
```

### 3. Running the backend locally

```bash
cd server
cp .env.example .env   # fill in BOT_TOKEN + SESSION_JWT_SECRET
npm install
npm run dev             # node --watch server.js, listens on :8787
```

## What NOT to do

- Don't move `BOT_TOKEN` (or the verification HMAC logic) into `App.js` or
  any other browser-shipped bundle — that defeats the entire point of
  server-side verification.
- Don't trust `user` fields from `initData` before step 5 (hash comparison)
  passes — an attacker can put anything they want in the unsigned parts of
  a crafted query string.
- Don't skip the `auth_date` replay check — a previously-valid `initData`
  string stays hash-valid forever unless you also enforce an age limit.
