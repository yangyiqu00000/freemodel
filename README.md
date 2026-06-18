<div align="center">

# 💲 FreeModel MenuBar

**Stop hand-editing `~/.codex/config.toml` every time you switch API keys.**

A tiny macOS menu bar app that lets you rotate LLM providers inside
[OpenAI Codex](https://github.com/openai/codex) with one click — and ships
with a built-in local router that fixes the protocol quirks nobody
warned you about.

[![macOS](https://img.shields.io/badge/macOS-13%2B-blue?logo=apple)](#-system-requirements)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange?logo=swift)](#-tech-stack)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Release](https://img.shields.io/github/v/release/yangyiqu00000/freemodel)](https://github.com/yangyiqu00000/freemodel/releases)
[![Stars](https://img.shields.io/github/stars/yangyiqu00000/freemodel?style=social)](https://github.com/yangyiqu00000/freemodel)

[⬇️ Download v0.0.1](https://github.com/yangyiqu00000/freemodel/releases/latest) · [📖 中文文档](FreeModelMenuBar/README.md) · [🐛 Report a bug](https://github.com/yangyiqu00000/freemodel/issues)

</div>

---

## ✨ What is this?

You're juggling three API keys. Maybe four. You've got FreeModel, DeepSeek,
OpenRouter, ModelScope… and every time you want to test a prompt with
provider X, the ritual looks like this:

```bash
vim ~/.codex/config.toml   # edit provider, paste key, change base_url
codex                      # restart
# test
vim ~/.codex/config.toml   # again
codex                      # again
```

**No more.**

FreeModel MenuBar lives in your menu bar (look for the 💲). Click it,
pick an account, done. Your `config.toml` is rewritten for you, the
local router reloads, and Codex is none the wiser.

> 🪄 It's the missing "settings UI" Codex never had.

---

## 🎯 Features you'll actually use

### 🔁 Multi-account switching that doesn't suck
- **Unlimited accounts** — every provider, every key, in one place
- **One-click rotation** — pick an account from the menu, that's it
- **Keychain-backed** — your keys never touch a plaintext file
- **Two refresh modes**:
  - 🌐 *Web console mode*: scrapes your dashboard via a sandboxed WebKit
    window — no API key needed
  - 🔑 *API mode*: fast balance check via the provider's billing endpoint

### 📊 Status bar that actually tells you something
- Color-coded balance (🟢 healthy → 🟠 low → 🔴 critical)
- Custom alert thresholds per provider
- Live balance & quota right in the menu bar icon

### ⚡ Built-in local router (the part nobody asked for, but everybody needs)

Spin up a local Node.js sidecar that exposes a **OpenAI-compatible
endpoint at `http://127.0.0.1:<port>/v1`**. Why? Because Codex uses
the Responses API, and most third-party providers only speak
Chat Completions. The router fixes that, transparently:

| Headache | What the router does |
|---|---|
| `unknown variant developer` (Responses → Chat) | Auto-maps `developer` → `system` |
| Client aborts mid-stream | Tears down the upstream TCP so you don't get billed for the rest |
| Provider returns plain error JSON | Wraps it in a proper `event: response.failed` SSE |
| Non-OpenAI base URLs | Just works — point Codex at `127.0.0.1` and forget |

> Zero npm dependencies. The entire router is plain `node:http` +
> `node:https`. Runs out of the box.

### 🛠️ Developer-grade console
- Dark-themed rolling log of the last 50 requests
- Click any row to see the full request/response
- Quick links to each provider's console & API docs

### 🧘 Designed not to wake you up
- Listens to `NSWorkspace.didWakeNotification` — if your Mac sleeps,
  the router health-checks itself on wake and **hot-restarts if it died**
- No background daemons, no launchctl, no mystery ports left open

---

## 📦 Install

You have two options. Pick the one that hurts less.

### Option A: Grab the DMG (recommended)

1. Head to [**Releases → v0.0.1**](https://github.com/yangyiqu00000/freemodel/releases/latest)
2. Download `FreeModelMenuBar-0.0.1.dmg`
3. Open it, drag the app into `/Applications`
4. Launch it — look for 💲 in your menu bar
5. Click 💲 → **Settings** → add your first account

> **First-launch tip:** if macOS Gatekeeper complains, right-click
> the app in Finder → **Open** → **Open** again. This is a one-time
> thing for ad-hoc-signed apps.

### Option B: Build it yourself

You only need this if you want to hack on the code.

```bash
git clone https://github.com/yangyiqu00000/freemodel.git
cd freemodel/FreeModelMenuBar
./build.sh
```

The script compiles, ad-hoc signs, and drops a fresh
`FreeModelMenuBar.app` on your Desktop. Done.

**Requirements:** macOS 13+, Xcode 15+, Node 16+ (only if you use the
local router feature — the menu bar app itself is pure Swift).

---

## 🚀 Quick start

```text
   ┌──────────────────────────────────────────────────────────┐
   │  1. Open FreeModelMenuBar (💲 in menu bar)               │
   │  2. Settings → Accounts → +  (add your API key)          │
   │  3. Settings → Router  → Enable (toggle on)             │
   │  4. In Codex: set base_url to http://127.0.0.1:<port>   │
   │  5. Back in 💲 menu, click your account name → done      │
   └──────────────────────────────────────────────────────────┘
```

That's the whole flow. Now go burn your `config.toml` backups.

---

## 🧩 Tech stack

| Layer | What we use | Why |
|---|---|---|
| UI | SwiftUI + `MenuBarExtra` | Native, no Electron, no 200MB binary |
| Lifecycle | AppKit + `NSWorkspace` notifications | Wake-from-sleep auto-heal |
| Storage | macOS Keychain | Keys never on disk in plaintext |
| Router | Node.js (`node:http` / `node:https`) | Zero deps, ~300 lines |
| Process model | `Process` + `readabilityHandler` | Clean shutdown, no zombie ports |

Project layout:

```text
FreeModelMenuBar/
├── FreeModelMenuBar/        # The Swift app
│   ├── CodexInjector/       # Provider / Config / Auth layers
│   │   ├── AuthLayer/       # Keychain + JSON store
│   │   ├── ConfigLayer/     # TOML read/write (no TOMLKit dep)
│   │   └── ProviderLayer/   # Catalog & presets
│   ├── router_sidecar.js    # The local Responses → Chat router
│   ├── MenuContent.swift    # The 💲 menu you actually see
│   └── ...
├── scripts/                 # Static checks for the router
├── docs/                    # Design docs & implementation plans
└── build.sh                 # One-shot build → ad-hoc sign → desktop
```

For the full feature list (in Chinese), see
[`FreeModelMenuBar/README.md`](FreeModelMenuBar/README.md).

---

## ❓ FAQ

**Q: Is this safe? You're rewriting my `config.toml` for me.**
A: The app reads & writes `~/.codex/config.toml` directly. We never
   send it anywhere. The only network calls are to the providers you
   explicitly add. Source is 100% Swift — go read it.

**Q: Why a router? Can't Codex just use the right base URL?**
A: Codex speaks the Responses API. Most third-party providers
   only support Chat Completions. The router bridges that gap
   *locally* — no third-party proxy, no data leaves your machine
   except the upstream call you asked for.

**Q: Does it work on Apple Silicon? Intel?**
A: Both. Universal binary (`x86_64 arm64`).

**Q: Why is the signing "ad-hoc"? Can I notarize it?**
A: Ad-hoc is fine for personal use and casual sharing. Notarization
   needs a $99/year Apple Developer account — happy to set it up
   if there's demand.

**Q: Will this work with Claude Code / Cursor / Aider?**
A: Anything that speaks OpenAI Chat Completions or Responses works.
   Point `base_url` at the local router and you're set.

**Q: My provider isn't in the catalog.**
A: Settings → Providers → **+** → add a custom base URL, model name,
   and API key. Works with any OpenAI-compatible endpoint.

---

## 🗺️ Roadmap

- [x] Multi-account rotation
- [x] Local Responses → Chat router
- [x] Wake-from-sleep auto-heal
- [x] Keychain-backed credential storage
- [ ] Configurable rate limit / retry budget per provider
- [ ] Per-account model aliases (`/v1/models/gpt-4` → upstream's `gpt-4-turbo`)
- [ ] Token-usage analytics (last 7 / 30 days)
- [ ] Menubar icon theming
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
