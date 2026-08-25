# Port Plan: ai-usage → Noctalia v5 (Luau)

Status: PLANNED · Branch: `luau-v5` · Source of truth for the port.
Base: v0.5.1 QML implementation (`main`, 4346 lines, 62 tests).

## 1. Why

Noctalia v4 (Quickshell) is officially frozen ("no longer maintained → use Noctalia v5").
v5 plugins are Luau scripts with a declarative manifest, a sandboxed runtime API
(http/fs/state/ui), and a live community registry (`noctalia-dev/community-plugins`).
Everything we build from now on targets v5 ("теперь на нем все будет в дальнейшем").

Goal: feature-parity port of ai-usage to a v5 Luau plugin, published as
`apilot/ai-usage-v5` in the community registry. The v4 plugin stays on `main`
(receives the legacy-registry PR already opened); the port lives on this branch
until it replaces `main`.

## 2. What exists today (inventory)

| File | Lines | Role |
|---|---|---|
| Logic.js | 1084 | Pure layer: PROVIDERS registry (zai, deepseek, openrouter, kimi, claude, anthropic), tolerant parsers, crypto envelope (pure SHA-256/HMAC + openssl call sites in Main), severity/money/plan helpers, form normalize/merge, migration |
| Main.qml | 663 | Service: fetch orchestration (XHR + runShell/curl for Claude), fetch slots + reaper, at-rest encryption (openssl subprocess, env-only secrets), Claude OAuth chain w/ write-back, settings migration, state exposed to views |
| Panel.qml | 566 | Tabs per provider, metric cards, severity colors, cached/failing UX |
| Settings.qml | 475 | Provider CRUD (add/edit form, keyless flow), refresh interval, background toggle |
| DesktopWidget.qml | 304 | Draggable card, validity countdown, severity accent |
| BarWidget.qml | 244 | Multi-provider capsule `Z 68% \| DS $6.76`, per-segment click-to-select |
| ControlCenterWidget.qml | 49 | Compact row + tooltip |
| UsageBar/ProviderChip | 76 | Shared visuals |
| i18n/{en,ru}.json | 170 | Translations |
| tests/logic.test.mjs | 715 | 62 unit tests (parsers, crypto FIPS/RFC vectors, migration, forms) |
| tests/bench/ | ~600 | Offline QML smoke harness (NOT portable — replaced by Luau tests + live v5) |

Feature set to preserve: 6 providers, bar capsule with per-segment switching,
panel with per-provider tabs, provider CRUD with safe key editing (stored key
never re-loaded; empty submit keeps it), encrypted-at-rest keys, Claude keyless
OAuth flow, cached last-good degradation, per-provider error surfacing.

## 3. Target structure (v5)

```
ai-usage/                      # plugin dir name in community-plugins fork
  plugin.toml                  # manifest: id "apilot/ai-usage", plugin_api, [[service]] [[widget(bar)]] [[panel]] [[setting]]
  preview.webp                 # 960x540 (convert from media/preview.png)
  README.md
  translations/
    en.json  ru.json
  src/
    logic.luau                 # pure module: parsers, helpers, envelope crypto math (NO runtime calls)
    providers.luau             # registry: 6 provider descriptors (urls, headers, parse fn refs)
    store.luau                 # providers.json CRUD in pluginDataDir(), migration from v4 settings
    fetch.luau                 # http orchestration: slots, errors, cached entries, claude chain
    crypto.luau                # at-rest envelope: sha256/hmac (pure) + openssl via runAsync (decision point)
    bar.luau                   # capsule widget (all enabled providers, segment select, scroll-cycle)
    panel.luau                 # tabs, metric cards, provider CRUD forms
    desktop.luau               # desktop card (phase 2 — optional)
  tests/
    logic_test.luau            # ported 62 tests + runner.lua (lua5.1-compatible, no external deps)
    runner.lua
```

Manifest sketch (validated against registry rules):

```toml
[plugin]
id = "apilot/ai-usage"
name = "AI Usage"
version = "1.0.0-alpha.1"
plugin_api = 24          # min for runAsync argv form; verify against beta.9 header
description = "..."      # <= 120 chars
tags = ["bar", "panel", "desktop", "ai", "indicator"]

[[service]]
script = "src/service.luau"   # tiny: boots fetch loop, owns state

[[widget]]
name = "ai-usage-bar"
script = "src/bar.luau"

[[panel]]
name = "ai-usage-panel"
script = "src/panel.luau"

# Declarative settings: refresh_minutes (select), show_background (toggle).
# Provider list is NOT a setting (no list type) → store.luau + panel CRUD.
```

## 4. Subsystem mapping (v4 → v5)

| v4 | v5 | Notes |
|---|---|---|
| XHR `startFetch` | `noctalia.http(req, cb)` | Native headers → **curl no longer needed anywhere**; Claude User-Agent works natively |
| Process + curl (claude) | `noctalia.http` POST + `fs.readFile/writeFile` | Creds read/write via fs API |
| Process + openssl (crypto) | `noctalia.runAsync(openssl…)` | **No env/stdin in runAsync** → decision point §5.1 |
| settings.json + pluginSettings | declarative `[[setting]]` + `pluginDataDir()/providers.json` | Own store for the provider list |
| qs Process slots/reaper | `state` + fetch slots in fetch.luau | Port slot discipline; watchdog per request |
| Timer/pollTimer | service loop + `setUpdateInterval` | ai-usagebar poller pattern as reference |
| QML views + N* widgets | `ui.*` declarative trees in bar/panel render | No anchors/layout pitfalls; ui.input/select for CRUD |
| pluginApi.tr + i18n/ | `noctalia.tr` + translations/{en,ru}.json | Key parity |
| signals/property bindings | `state.watch` pub/sub | Service publishes `entries/errors/fetching`; widgets re-render |
| bench harness (qs -p) | lua5.1 unit runner + live v5 manual | UI trees are declarative → fewer smoke needs |
| ProviderChip monogram+color | ui.glyph/label + ui.box color | Brand colors from providers.luau |

## 5. Decision points (need user before/during Phase 2)

### 5.1 Crypto at rest (blocker for store.luau design)
- **(a) Plaintext keys in providers.json + 0600-ish protection by host** — community
  norm (deepseek_usage stores `api_key` plaintext). Fastest, honest.
- **(b) Keep envelope, invoke openssl via runAsync** — secrets (key AND passphrase)
  land in argv, visible in /proc. Worse than v4, arguably theater.
- **(c) RECOMMENDED: (a) now + upstream issue** asking for env/stdin in runAsync
  (or a native crypto API); re-introduce envelope when available. providers.json
  schema keeps an `enc:v1:`-ready string field so migration back is trivial.
  Document threat model in README (same honesty as v4).

### 5.2 v5 shell install timing
Live validation requires Noctalia v5 (beta.9). Options: install early (Phase 1,
parallel to current shell — different product, may coexist) vs install late
(after logic+service ported, test everything at once). RECOMMENDED: early,
small coexistence check first (does beta.9 even run here?), because API-shape
surprises (http timeout, writeFile perms) feed back into design.

### 5.3 Scope trims for v1 of the port
- Desktop widget: phase 2 (registry accepts bar+panel first).
- Control-center widget: no v5 equivalent entry point → drop (panel covers it).
- Anthropic Admin API + Claude OAuth: port WITH everything (they're the
  differentiators); Claude refresh write-back needs `fileInfo`/perms check (no
  chmod API — verify host writeFile mode; if world-readable, document + guard).

## 6. Phases (each ends with a validation gate)

**Phase 0 — scaffold (~0.5h)** [approval: this plan]
- Branch `luau-v5` (done), repo restructure-free: add plan (this file), fetch
  `noctalia.d.luau` (gitignored), `.luaurc` (nonstrict), stylua config.
- Gate: `stylua --check src/ tests/` clean on empty stubs; plugin.toml drafted.

**Phase 1 — logic.luau TDD port (~4-6h)** [pure, no runtime deps]
- Port Logic.js → logic.luau + providers.luau in **Lua 5.1-compatible subset**
  (no `+=`, no string interpolation, no type annotations) so tests run under
  system `lua5.1` today and under Luau in v5 later.
- Port all 62 tests → tests/logic_test.luau + runner.lua (assert-based, exit
  code). Crypto math (sha256/hmac/b64url) ports 1:1 from the tested JS with
  the FIPS/RFC vectors as the acceptance gate.
- Gate: `lua5.1 tests/runner.lua` → 62/62 green.

**Phase 2 — store + service (~4-5h)** [needs 5.1 + 5.2 decisions]
- store.luau: providers.json CRUD, v4 settings.json migration (read old file
  if present → convert → keep backup), envelope-ready schema.
- fetch.luau: poller service (reference ai-usagebar service.luau: MIN_GAP,
  busy-timer, error classification), per-provider slots, cached last-good,
  claude chain (read creds → refresh+write-back → usage), 300s claude clamp,
  **http watchdog** (no timeout field in HttpRequest — wrap with own deadline).
- Gate: lua5.1 unit tests for store/migration; live v5: service fetches z.ai
  + deepseek from migrated providers.json (needs v5 installed).

**Phase 3 — bar.luau (~2-3h)**
- Capsule: chip monograms + compact values, `·`-separated or `|`, active bold
  (setColor role), click = select provider, wheel = cycle (v4 borrow we never
  shipped), tooltip rows per provider, ⚠/… states, cached-dim.
- Gate: live on v5 — segments render, click/wheel work, states degrade.

**Phase 4 — panel.luau (~4-5h)**
- Tabs per provider; metric cards (label/value/detail/severity color/reset
  countdown via nowMs tick); cached badge; provider CRUD: add/edit forms
  (ui.input/select/button), safe key editing semantics identical to v4
  (stored key never re-seeded; empty keeps; hint shown), delete confirm.
- Gate: live CRUD roundtrip on v5 incl. migration path from v4 settings.

**Phase 5 — i18n + thumbnail + README (~1-2h)**
- translations/{en,ru}.json full parity; preview.webp from media/preview.png;
  README rewrite (v5 install, screenshots reused, security section per 5.1).
- Gate: `noctalia.tr` parity check; registry CI rules respected (description
  ≤120, semver, tags lowercase from list).

**Phase 6 — publish (~1h)**
- Fork community-plugins → PR `apilot/ai-usage` with network/fs/process
  disclosure paragraph (http GETs ×6 + 1 POST claude refresh; fs: providers.json
  + ~/.claude read/write; subprocess: openssl only if 5.1=(b)).
- Gate: CI validate green; plugin listed.

Total estimate: ~16-21h focused work.

## 7. Risks / unknowns (verify early in Phase 2)

| # | Risk | Mitigation |
|---|---|---|
| R1 | `http` has no timeout field | Own deadline watchdog per request (timer + ignore late cb); report upstream |
| R2 | `runAsync` argv-only → secrets visible | Decision 5.1; prefer (c) |
| R3 | `writeFile` perms unknown (claude creds need 0600) | Probe on v5 (fileInfo); if 0644 — document + upstream issue |
| R4 | v5 beta.9 API drift vs noctalia.d.luau | Pin plugin_api; smoke early (5.2) |
| R5 | No list-type settings (by design) | store.luau — already the plan |
| R6 | Lua 5.1 subset friction (no continue/goto) | Style rules in logic.luau header; stylua keeps it honest |
| R7 | bar render constraints (no input/scroll in bar) | Capsule needs labels only — fine |
| R8 | Both shells on one machine confusion | v5 config separate; port tested against pluginDataDir copies, never touches live v4 settings until migration is explicit |

## 8. Non-goals (explicit)

- No Rust binary / no ai-usagebar dependency (same as v4).
- No telemetry.
- No new providers during the port (Moonshot/MiniMax etc. after v1 ships;
  vendor-endpoints.md reference already parked in ai_usage/ docs).
- v4 `main` branch: maintenance-only from now on.

## 9. Change log

- 2026-08-25: plan drafted on `luau-v5` (this file).
