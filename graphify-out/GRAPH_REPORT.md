# Graph Report - /home/forget/LMArena  (2026-07-30)

## Corpus Check
- 76 files · ~91,005 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 528 nodes · 969 edges · 46 communities (25 shown, 21 thin omitted)
- Extraction: 93% EXTRACTED · 7% INFERRED · 0% AMBIGUOUS · INFERRED: 66 edges (avg confidence: 0.52)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- Community 0
- Community 1
- Community 2
- Community 3
- Community 4
- Community 5
- Community 6
- Community 7
- Community 8
- Community 9
- Community 10
- Community 11
- Community 12
- Community 13
- Community 14
- Community 15
- Community 16
- Community 17
- Community 18
- Community 19
- Community 20
- Community 21
- Community 22
- Community 23
- Community 24
- Community 25
- Community 26
- Community 27
- Community 28
- Community 29
- Community 30
- Community 31
- Community 32
- Community 33
- Community 34
- Community 35
- Community 36
- Community 37
- Community 39
- Community 43

## God Nodes (most connected - your core abstractions)
1. `BaseBridgeTest` - 55 edges
2. `api_chat_completions()` - 24 edges
3. `_m()` - 21 edges
4. `FakeStreamResponse` - 18 edges
5. `debug_print()` - 17 edges
6. `BrowserFetchStreamResponse` - 15 edges
7. `FakeStreamContext` - 15 edges
8. `get_initial_data()` - 14 edges
9. `UserscriptProxyStreamResponse` - 14 edges
10. `startup_event()` - 13 edges

## Surprising Connections (you probably didn't know these)
- `TestArenaOriginAndCookieScoping` --uses--> `BaseBridgeTest`  [INFERRED]
  Storage/tests/test_arena_origin_and_cookie_scoping.py → Storage/tests/_stream_test_utils.py
- `_FakePage` --uses--> `BaseBridgeTest`  [INFERRED]
  Storage/tests/test_camoufox_window_mode.py → Storage/tests/_stream_test_utils.py
- `TestCamoufoxWindowMode` --uses--> `BaseBridgeTest`  [INFERRED]
  Storage/tests/test_camoufox_window_mode.py → Storage/tests/_stream_test_utils.py
- `_FakeContext` --uses--> `BaseBridgeTest`  [INFERRED]
  Storage/tests/test_localstorage_arena_auth_recovery.py → Storage/tests/_stream_test_utils.py
- `_FakePage` --uses--> `BaseBridgeTest`  [INFERRED]
  Storage/tests/test_localstorage_arena_auth_recovery.py → Storage/tests/_stream_test_utils.py

## Import Cycles
- None detected.

## Communities (46 total, 21 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.06
Nodes (48): BaseModel, AnthropicMessageRequest, _arena_auth_cookie_specs(), _arena_origin_candidates(), BrowserFetchStreamResponse, camoufox_proxy_worker(), _cleanup_userscript_proxy_jobs(), _detect_arena_origin() (+40 more)

### Community 1 - "Community 1"
Cohesion: 0.07
Nodes (63): click_turnstile(), Attempts to locate and click the Cloudflare Turnstile widget. Based on gpt4free…, get_models(), Load models from file., save_models(), anthropic_messages(), api_chat_completions(), check_link_expiry() (+55 more)

### Community 2 - "Community 2"
Cohesion: 0.09
Nodes (39): _capture_ephemeral_arena_auth_token_from_cookies(), _combine_split_arena_auth_cookies(), _decode_arena_auth_session_token(), _decode_jwt_payload(), _derive_supabase_auth_base_url_from_arena_auth_token(), extract_supabase_anon_key_from_text(), get_arena_auth_token_expiry_epoch(), get_next_auth_token() (+31 more)

### Community 3 - "Community 3"
Cohesion: 0.07
Nodes (30): Any, _apply_config_defaults(), get_config(), get_config_file(), get_default_config(), _get_global_state(), is_port_free(), Configuration management for LMArena (+22 more)

### Community 4 - "Community 4"
Cohesion: 0.16
Nodes (27): _arch(), _build_html_from_js(), _cf_bin(), _cf_installed(), _cf_version(), _curl(), _gh_releases(), install_cf() (+19 more)

### Community 5 - "Community 5"
Cohesion: 0.13
Nodes (9): FakeStreamContext, FakeStreamResponse, A fake response for httpx.AsyncClient.stream context manager., A fake async context manager for httpx.AsyncClient.stream., TestStream301RedirectRetriesViaUserscriptProxy, TestStream403RecaptchaRetries, TestStream403SwitchesToChromeFetch, TestStream429RespectsRetryAfter (+1 more)

### Community 6 - "Community 6"
Cohesion: 0.11
Nodes (17): app, cookieParser, cors, crypto, express, jwt, TODO: port get_initial_data() from the Python bridge here — fetch a, { readConfig, writeConfig } (+9 more)

### Community 7 - "Community 7"
Cohesion: 0.17
Nodes (20): _camoufox_proxy_signup_anonymous_user(), find_chrome_executable(), get_cached_recaptcha_token(), get_recaptcha_settings(), get_recaptcha_v3_token(), get_recaptcha_v3_token_with_chrome(), _m(), _maybe_inject_arena_auth_cookie_from_localstorage() (+12 more)

### Community 8 - "Community 8"
Cohesion: 0.16
Nodes (19): AccessGate(), api, App(), BarsChart(), BOOT_LINES, COLORS, Dashboard(), DonutChart() (+11 more)

### Community 9 - "Community 9"
Cohesion: 0.10
Nodes (19): cookie-parser, cors, dotenv, express, jsonwebtoken, dependencies, cookie-parser, cors (+11 more)

### Community 10 - "Community 10"
Cohesion: 0.13
Nodes (7): BaseBridgeTest, Helper to write or update the mock config.json., Base class for LMArenaBridge tests, handling common setup/teardown., TestAuthTokenFallbackFromBrowserCookies, TestCamoufoxProxyAnonymousSignup, TestChromeFetchWindowMode, TestStreamProxyActiveSkipsSidechannelRecaptchaMint

### Community 11 - "Community 11"
Cohesion: 0.14
Nodes (3): TestStreamNoAuthTokenPrefersUserscriptProxy, TestStreamUserscriptProxyFetchStartDelayNoFallback, TestStreamUserscriptProxyStatusTimeoutFallback

### Community 12 - "Community 12"
Cohesion: 0.19
Nodes (4): _FakeElement, _FakeMouse, _FakePage, TestTurnstileClickFallback

### Community 13 - "Community 13"
Cohesion: 0.24
Nodes (12): BaseException, _cancel_background_task(), _consume_background_task_exception(), is_execution_context_destroyed_error(), _is_windows(), _maybe_apply_camoufox_window_mode(), _normalize_camoufox_window_mode(), Browser and OS window utility functions for LMArenaBridge. Handles: - Windows… (+4 more)

### Community 15 - "Community 15"
Cohesion: 0.28
Nodes (3): _FakeContext, _FakePage, TestLocalStorageArenaAuthRecovery

### Community 16 - "Community 16"
Cohesion: 0.33
Nodes (3): _FakeContext, _FakePage, TestProvisionalUserIdSync

### Community 17 - "Community 17"
Cohesion: 0.29
Nodes (4): get_model_usage_stats(), Global state management for LMArenaBridge. Holds in-memory state that needs to…, set_model_usage_stats(), defaultdict

### Community 18 - "Community 18"
Cohesion: 0.52
Nodes (6): analyze(), _b64url_decode(), decode_jwt_payload(), decode_session_cookie(), main(), If the token is `base64-<json>`, return the parsed session dict.

### Community 21 - "Community 21"
Cohesion: 0.70
Nodes (4): get_updates(), run_echo_mode(), send_message(), tail_and_forward()

## Knowledge Gaps
- **38 isolated node(s):** `HTTPStatus`, `QuickStart.sh script`, `Setuper.sh script`, `XDG_RUNTIME_DIR`, `ICONS` (+33 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **21 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `BaseBridgeTest` connect `Community 10` to `Community 5`, `Community 11`, `Community 12`, `Community 14`, `Community 15`, `Community 16`, `Community 20`, `Community 22`, `Community 23`, `Community 25`, `Community 26`?**
  _High betweenness centrality (0.269) - this node is a cross-community bridge._
- **Why does `click_turnstile()` connect `Community 1` to `Community 12`, `Community 13`?**
  _High betweenness centrality (0.250) - this node is a cross-community bridge._
- **Why does `_FakePage` connect `Community 12` to `Community 10`?**
  _High betweenness centrality (0.246) - this node is a cross-community bridge._
- **Are the 29 inferred relationships involving `BaseBridgeTest` (e.g. with `TestArenaOriginAndCookieScoping` and `TestAuthTokenFallbackFromBrowserCookies`) actually correct?**
  _`BaseBridgeTest` has 29 INFERRED edges - model-reasoned connections that need verification._
- **Are the 5 inferred relationships involving `FakeStreamResponse` (e.g. with `TestStream301RedirectRetriesViaUserscriptProxy` and `TestStream403RecaptchaRetries`) actually correct?**
  _`FakeStreamResponse` has 5 INFERRED edges - model-reasoned connections that need verification._
- **What connects `HTTPStatus`, `QuickStart.sh script`, `Setuper.sh script` to the rest of the system?**
  _38 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.05970149253731343 - nodes in this community are weakly interconnected._