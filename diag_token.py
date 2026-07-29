#!/usr/bin/env python3
"""
Diagnostic for `arena-auth-prod-v1` tokens.

Run on the server next to config.json:
    python3 diag_token.py [path/to/config.json]

It decodes every token in `auth_tokens` / `auth_token` and prints the key JWT
claims so you can tell WHY arena.ai returns 401 {"message":"User not found"}:
  - exp         : is the JWT actually expired? (bridge only checks this)
  - is_anonymous: anonymous accounts get garbage-collected by arena.ai
  - iss         : origin check (arena.ai vs lmarena.ai user pools can differ)
  - sub         : the user id arena.ai looks up and fails to find
"""
import base64
import json
import os
import sys
import time


def _b64url_decode(s: str) -> bytes:
    s += "=" * ((4 - len(s) % 4) % 4)
    return base64.urlsafe_b64decode(s.encode())


def decode_jwt_payload(token: str):
    token = (token or "").strip()
    if token.count(".") < 2:
        return None
    try:
        return json.loads(_b64url_decode(token.split(".")[1]).decode())
    except Exception as e:
        return {"_decode_error": str(e)}


def decode_session_cookie(token: str):
    """If the token is `base64-<json>`, return the parsed session dict."""
    token = (token or "").strip()
    if not token.startswith("base64-"):
        return None
    try:
        return json.loads(_b64url_decode(token[len("base64-"):]).decode())
    except Exception as e:
        return {"_decode_error": str(e)}


def analyze(token: str, idx: int):
    print(f"\n===== token #{idx} =====")
    print(f"stored value (head): {token[:40]}...")
    print(f"length: {len(token)}")

    session = decode_session_cookie(token)
    if isinstance(session, dict) and "_decode_error" not in session:
        print("format: base64 session cookie")
        access = str(session.get("access_token") or "").strip()
        refresh = str(session.get("refresh_token") or "").strip()
        print(f"  has access_token : {bool(access)} (len={len(access)})")
        print(f"  has refresh_token: {bool(refresh)} (len={len(refresh)})")
        try:
            print(f"  expires_at       : {session.get('expires_at')} "
                  f"({time.ctime(session.get('expires_at') or 0)})")
        except Exception:
            print(f"  expires_at       : {session.get('expires_at')}")
        if not access:
            print("  !! session has NO access_token -> cannot authenticate")
            return
        jwt = decode_jwt_payload(access)
        target = access
    else:
        print("format: raw (not base64 session) -> treating as JWT/opaque")
        jwt = decode_jwt_payload(token)
        target = token

    if not isinstance(jwt, dict):
        print(f"  could not decode JWT payload: {jwt}")
        return

    now = int(time.time())
    exp = jwt.get("exp")
    print(f"  JWT iss         : {jwt.get('iss')}")
    print(f"  JWT aud         : {jwt.get('aud')}")
    print(f"  JWT sub (user)  : {jwt.get('sub')}")
    print(f"  JWT exp         : {exp} ({time.ctime(exp) if exp else '?'})")
    print(f"  JWT is_anonymous: {jwt.get('is_anonymous')}")
    print(f"  JWT role        : {jwt.get('role')}")

    if exp is not None:
        delta = int(exp) - now
        if delta > 0:
            print(f"  -> JWT NOT expired by exp ({delta}s remaining)")
        else:
            print(f"  -> JWT EXPIRED {-delta}s ago")

    # The bridge only checks `exp`, but arena.ai also 401s when the USER row is gone.
    print("\n  DIAGNOSIS:")
    if jwt.get("is_anonymous") is True:
        print("   * anonymous account -> likely garbage-collected by arena.ai")
        print("     (JWT still valid by signature/exp, but user row missing => 'User not found')")
    iss = str(jwt.get("iss") or "")
    if "lmarena" in iss and "arena" not in iss.replace("lmarena", ""):
        print("   * issuer looks like lmarena.ai but the bridge talks to arena.ai")
        print("     -> possible user-pool mismatch; get the token from arena.ai")
    if exp is not None and int(exp) - now <= 0:
        print("   * JWT expired -> get a fresh cookie")
    print("   (if none of the above, the account was probably deleted/banned)")


def main():
    cfg_path = sys.argv[1] if len(sys.argv) > 1 else "config.json"
    if not os.path.exists(cfg_path):
        print(f"config not found: {cfg_path}")
        return 1
    with open(cfg_path, "r", encoding="utf-8") as f:
        cfg = json.load(f)

    tokens = list(cfg.get("auth_tokens") or [])
    if not tokens:
        single = str(cfg.get("auth_token") or "").strip()
        if single:
            tokens = [single]
    bc = cfg.get("browser_cookies")
    if isinstance(bc, dict) and bc.get("arena-auth-prod-v1"):
        tokens.append(bc["arena-auth-prod-v1"])

    if not tokens:
        print("no tokens found in config")
        return 1

    print(f"found {len(tokens)} token(s)")
    for i, t in enumerate(tokens):
        analyze(str(t or "").strip(), i)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
