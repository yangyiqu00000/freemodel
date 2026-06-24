<div align="center">

# 💲 FreeModel MenuBar

**One tiny macOS menu bar app. Three headaches gone.**

> Stop hand-editing `~/.codex/config.toml`. Stop wondering how much
> credit you have left. Stop restarting Codex just to switch keys.

[English](README.md) · [中文](README.zh.md)

[![macOS](https://img.shields.io/badge/macOS-13%2B-blue?logo=apple)](#-system-requirements)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange?logo=swift)](#-tech-stack)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Release](https://img.shields.io/github/v/release/yangyiqu00000/freemodel)](https://github.com/yangyiqu00000/freemodel/releases)
[![Stars](https://img.shields.io/github/stars/yangyiqu00000/freemodel?style=social)](https://github.com/yangyiqu00000/freemodel)

[⬇️ Download v0.0.3](https://github.com/yangyiqu00000/freemodel/releases/latest) · [🐛 Report a bug](https://github.com/yangyiqu00000/freemodel/issues)

</div>

---

## ✨ Why FreeModel MenuBar?

If you use [OpenAI Codex](https://github.com/openai/codex) with anything
other than the official OpenAI endpoint, you've been through this loop:

```text
vim ~/.codex/config.toml   # edit provider, paste key, change base_url
codex                      # restart
# test
vim ~/.codex/config.toml   # edit again
codex                      # restart again
# ... and your balance? who knows.
```

**FreeModel MenuBar replaces that whole ritual with a click in the menu bar.**

It's deliberately small. It's not a proxy manager, not an IDE, not a CLI
replacement. It's a **status-bar switchboard** for Codex — three things,
done well.

---

## 🎯 The three things it does

### 1. 🌐 Unify every API into the Responses protocol

Codex speaks the **OpenAI Responses** API. Most third-party providers
only speak **Chat Completions** (or, increasingly, their own thing).

The app ships a tiny local router that **transparently translates
anything into Responses**. Add a provider, set its real base URL once,
and the router does the rest.

The magic consequence: in `~/.codex/config.toml`, you only ever write
**one** `base_url`:

```toml
base_url = "http://127.0.0.1:7842/v1"
```

That's it. Forever. Even if you switch from DeepSeek to OpenRouter to
some random gateway, **Codex never sees a different URL.**

> 🪄 Configure once. The rest is menu-bar clicks.

### 2. 🔁 Hot-swap accounts without restarting Codex

Click the 💲 icon → pick an account → **the switch happens live.**

- The router reloads its upstream config
- Codex keeps streaming; in-flight requests aren't disturbed
- No `killall codex`, no `codex` re-launch, no lost context

This is the whole point. The old workflow forced you to restart Codex
because `config.toml` was the source of truth. With the local router as
a stable middleman, **Codex is decoupled from the provider layer.**

> 🧘 Test three providers in a row without losing your place.

### 3. 💰 See your balance right in the menu bar

No more logging into dashboards. No more "is it $5 or $0.50 left?"

- 🟢 Healthy / 🟠 Low / 🔴 Critical — color-coded at a glance
- Custom alert thresholds per provider
- Auto-refresh on a schedule you control
- Click the menu bar item for a per-account breakdown

The router is local, but the **balance check** can hit each provider's
billing endpoint (or, for providers without one, scrape the dashboard
in a sandboxed WebKit window — your key never leaves your machine).

> 😌 Quiet the "do I have enough credit?" anxiety.

---

## 🧩 The three setups it covers

The app doesn't try to be a kitchen sink. It supports **exactly three
configurations**, which together cover every way people use Codex:

| Setup | When to use it | `base_url` in `config.toml` | Router runs? |
|---|---|---|---|
| **A. Third-party + Responses conversion** | You're using DeepSeek / OpenRouter / ModelScope / any non-OpenAI Chat-Completions provider | `http://127.0.0.1:<port>/v1` | ✅ Yes |
| **B. Third-party, native Responses** | Provider already speaks Responses natively | `http://127.0.0.1:<port>/v1` | ⚪ Optional pass-through |
| **C. Official OpenAI** | You're using OpenAI directly | The provider's own `https://api.openai.com/v1` | ❌ No — read config directly |

**That's the entire surface area.** Three modes, mutually exclusive
in any given moment, switchable with one click.

> The router is opt-in: if you don't need protocol translation, you
> don't pay for it. The menu bar app works on its own — it can just
> read the official OpenAI config straight from `~/.codex/config.toml`
> and show you balance, no router, no Node, nothing extra running.

---

## 🚀 Quick start (90 seconds)

```text
   ┌──────────────────────────────────────────────────────────┐
   │  1. Install FreeModelMenuBar (DMG, drag to /Applications)│
   │  2. Click 💲 in the menu bar → Settings                  │
   │  3. Add an account (paste API key, pick provider)        │
   │  4. Pick your setup:                                     │
   │       A) Third-party → router ON  → done                 │
   │       B) Third-party native → router pass-through → done  │
   │       C) Official OpenAI  → no router, just balance      │
   │  5. In Codex config.toml, set base_url to                │
   │       http://127.0.0.1:<port>/v1   (one time, ever)      │
   │  6. From now on: click 💲 → switch account → it just works│
   └──────────────────────────────────────────────────────────┘
```

After step 5, you'll never touch `config.toml` again.

---

## 📦 Install

### Option A: Grab the DMG (recommended)

1. Head to [**Releases → v0.0.3**](https://github.com/yangyiqu00000/freemodel/releases/latest)
2. Download `FreeModelMenuBar-0.0.3.dmg`
3. Open it, drag the app into `/Applications`
4. Launch it — look for 💲 in your menu bar

> **First-launch tip:** if macOS Gatekeeper complains, right-click
> the app in Finder → **Open** → **Open** again. One-time thing for
> ad-hoc-signed apps.

### Option B: Build it yourself

```bash
git clone https://github.com/yangyiqu00000/freemodel.git
cd freemodel/FreeModelMenuBar
./build.sh
```

The script compiles, ad-hoc signs, and drops a fresh
`FreeModelMenuBar.app` on your Desktop.

**Requirements:** macOS 13+, Xcode 15+, Node 16+ (only needed for
**Setup A** — the menu bar app and Setups B/C work fine without it).

---

## ❓ FAQ

**Q: Is this safe? You're rewriting my `config.toml` for me.**
A: The app reads & writes `~/.codex/config.toml` directly. We never
   send it anywhere. The only network calls are to the providers you
   explicitly add. Source is 100% Swift — go read it.

**Q: Why do I need a local router? Can't Codex just use the right base URL?**
A: Two reasons:
   1. Codex uses Responses; most providers use Chat Completions. The
      router bridges that locally — no third-party proxy, no data
      leaves your machine except the upstream call you asked for.
   2. Decoupling. With the router as a stable middleman, **Codex
      never has to know which provider you're using.** You switch
      providers via the menu bar; the router swaps its upstream.

**Q: Does Setup A work with my favorite provider X?**
A: If it speaks OpenAI Chat Completions (most do), yes. The router
   does the protocol translation, plus a few quality-of-life fixes:
   - Maps `developer` role → `system` (some providers choke on `developer`)
   - Wraps plain errors in `event: response.failed` SSE
   - Tears down the upstream TCP when you stop generating (no silent
     token drain)

**Q: What if I just use official OpenAI?**
A: Use **Setup C**. The menu bar app reads your existing
   `~/.codex/config.toml` and shows balance. No router, no Node,
   no extra processes.

**Q: Does it work on Apple Silicon? Intel?**
A: Both. Universal binary (`x86_64 arm64`).

**Q: Will this work with Cursor / Claude Code / Aider?**
A: For Cursor: yes, point its OpenAI base URL at the local router.
   For the others: they don't use Codex's Responses API, so the
   "unified base URL" trick doesn't apply — but Setup C (balance
   monitoring) still works.

**Q: Why ad-hoc signing? Can I notarize?**
A: Ad-hoc is fine for personal use and casual sharing. Notarization
   needs a $99/year Apple Developer account — happy to set it up
   if there's demand.

---

## 🧪 Tech stack

| Layer | What we use | Why |
|---|---|---|
| UI | SwiftUI + `MenuBarExtra` | Native, no Electron, no 200MB binary |
| Lifecycle | AppKit + `NSWorkspace` notifications | Wake-from-sleep auto-heal |
| Storage | macOS Keychain | Keys never on disk in plaintext |
| Router | Node.js (`node:http` / `node:https`) | Zero deps, protocol auto-detect |
| Process model | `Process` + `readabilityHandler` | Clean shutdown, no zombie ports |

Project layout:

```text
FreeModelMenuBar/
├── FreeModelMenuBar/        # The Swift app
│   ├── CodexInjector/       # Provider / Config / Auth layers
│   │   ├── AuthLayer/       # Keychain + JSON store
│   │   ├── ConfigLayer/     # TOML read/write (no TOMLKit dep)
│   │   └── ProviderLayer/   # Catalog & presets
│   ├── router_sidecar.js    # The local Responses ↔ Chat router
│   ├── MenuContent.swift    # The 💲 menu you actually see
│   └── ...
├── scripts/                 # Static checks for the router
├── docs/                    # Design docs & implementation plans
└── build.sh                 # One-shot build → ad-hoc sign → desktop
```

---

## 🗺️ Roadmap

Already shipped:

- [x] Multi-account rotation, hot-swap, no restart
- [x] Three-mode setup (router / pass-through / official)
- [x] Local Responses ↔ Chat Completions router
- [x] Wake-from-sleep auto-heal
- [x] Keychain-backed credential storage
- [x] Menu-bar balance monitoring with color-coded alerts
- [x] **Anthropic Messages protocol support** — router now also translates
      Responses → Anthropic Messages for Claude-compatible endpoints
- [x] **Protocol auto-detection** — router detects upstream protocol from
      URL suffix (`/v1/messages` → Anthropic, `/v1/chat/completions` → Chat)
- [x] **Settings sidebar drag-and-drop** — reorder account cards intuitively
- [x] **v0.0.3: Router refactoring & hardening**
  - Protocol adapter registry (`registerProtocol`) — add a protocol in one function call
  - 55 unit tests for router pure functions (<1s, zero HTTP)
  - `require()` side-effect free — no server start on `require('./router_sidecar')`
  - Global state decoupling in `repairToolCallMessageOrder`
  - All hardcoded constants → `CONFIG` object, env-overridable via `PROXY_*` vars
  - Stream inactivity timeout (60s default, `PROXY_STREAM_TIMEOUT_MS`)
  - `reasoning_content` preserved across tool-call turns
  - Anthropic `tool_use` → `tool_result` adjacency enforced (synthetic missing results)

Coming next:

- [ ] **Per-provider usage tutorials** — guided first-run walkthroughs
      for each of Setup A / B / C, with screenshots
- [ ] **More third-party provider support** in the catalog
- [ ] **Customizable API quota refresh interval** per provider
- [ ] **Per-account model aliases** (`/v1/models/gpt-4` → upstream's `gpt-4-turbo`)
- [ ] **Token-usage analytics** (last 7 / 30 days)
- [ ] Notarized build (waiting on Apple Dev account — see FAQ)

PRs welcome. Issues are open. Star the repo if this saved you a `vim`.

---

## 🤝 Contributing

```bash
git clone https://github.com/yangyiqu00000/freemodel.git
cd freemodel
git checkout -b feature/your-thing
# hack away
git commit -m "feat: your thing"
gh pr create
```

A few guidelines:

- **Keep the router dependency-free.** It's a feature, not laziness.
- **No telemetry.** This is a local tool. Don't add network calls
  that aren't user-initiated.
- **Match the SwiftUI style** in `MenuContent.swift` — auto-layout,
  semantic colors, no hardcoded RGB.
- **Add a script in `scripts/`** if you add a non-trivial behavior
  to the router. The static checks there catch regressions.

For the deep-dive design notes, see
[`FreeModelMenuBar/docs/`](FreeModelMenuBar/docs/).

---

## 📄 License

[MIT](LICENSE) — do whatever, just don't blame us.

```
Copyright (c) 2026 yangyiqu00000
```

---

<div align="center">

**If this saved you from one more `vim config.toml`, give it a ⭐**

Made with ❤️ and a slightly unhealthy relationship with menu bar apps.

</div>
