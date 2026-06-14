# Multi Account Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add complete multi-account management with isolated FreeModel dashboard sessions and optional per-account API keys.

**Architecture:** Add an account persistence layer (`ProviderAccount`, `StoredCookie`, `AccountManager`) and make `BalanceManager` refresh the active account. FreeModel cookies are stored per account and sent as request headers, keeping multiple web sessions isolated.

**Tech Stack:** Swift 5, SwiftUI, AppKit, WebKit, UserDefaults, Keychain, xcodebuild.

---

### Task 1: Account Model And Persistence

**Files:**
- Create: `FreeModelMenuBar/AccountManager.swift`
- Create: `scripts/check_account_manager.swift`
- Modify: `FreeModelMenuBar.xcodeproj/project.pbxproj`

- [ ] Write a failing script that creates two accounts, switches active account, stores distinct cookies, reloads from an in-memory store, and verifies API key identifiers are account-scoped.
- [ ] Add `ProviderAccount`, `StoredCookie`, `AccountStorage`, `UserDefaultsAccountStorage`, `InMemoryAccountStorage`, and `AccountManager`.
- [ ] Add `AccountManager.swift` to the Xcode project and source build phase.
- [ ] Run `swift FreeModelMenuBar/FreeModelDashboardParser.swift FreeModelMenuBar/AccountManager.swift scripts/check_account_manager.swift` and confirm it passes.

### Task 2: Balance Refresh Uses Active Account

**Files:**
- Modify: `FreeModelMenuBar/BalanceManager.swift`
- Create: `scripts/check_multi_account_static.swift`

- [ ] Write a static check that rejects global dashboard cookie use in balance refresh and rejects startup keychain reads.
- [ ] Inject `AccountManager` into `BalanceManager`.
- [ ] Change dashboard requests to build a `Cookie` header from `accountManager.activeAccount.cookieRecords`.
- [ ] Persist refreshed balances back onto the active account.
- [ ] Keep API key validation explicit and per-account.
- [ ] Run parser, account manager, no-automatic-keychain, and multi-account static checks.

### Task 3: Login Window Saves Cookies To Selected Account

**Files:**
- Modify: `FreeModelMenuBar/FreeModelWebLoginWindowController.swift`

- [ ] Pass `AccountManager` into the login window.
- [ ] Use a non-persistent `WKWebsiteDataStore` for each login flow.
- [ ] Before login, clear prior web data for the window store.
- [ ] On navigation finish, capture FreeModel cookies and save them on the selected account.
- [ ] Refresh balance after cookies are saved.

### Task 4: Menu And Settings UI

**Files:**
- Modify: `FreeModelMenuBar/FreeModelMenuBarApp.swift`
- Modify: `FreeModelMenuBar/MenuContent.swift`
- Modify: `FreeModelMenuBar/SettingsView.swift`
- Modify: `FreeModelMenuBar/SettingsWindowController.swift`

- [ ] Create `AccountManager` as a `@StateObject` in the app and pass it to views/controllers.
- [ ] Add active account selector to menu content.
- [ ] Show balance and login state for the active account.
- [ ] Rework settings to list accounts, add/delete/rename/select accounts, login selected account, manage optional API key, and keep refresh interval.
- [ ] Preserve the rule that settings does not auto-read API keys.

### Task 5: Verification And Desktop Build

**Files:**
- Existing scripts and Xcode project.

- [ ] Run `swift scripts/check_account_manager.swift` through its required compile invocation.
- [ ] Run `swift scripts/check_no_automatic_keychain_reads.swift`.
- [ ] Run `swift scripts/check_multi_account_static.swift`.
- [ ] Run `swift scripts/check_settings_window.swift`.
- [ ] Run dashboard parser check.
- [ ] Run `plutil -lint FreeModelMenuBar.xcodeproj/project.pbxproj`.
- [ ] Run Release `xcodebuild`.
- [ ] Copy the built app to `/Users/yyq/Desktop/FreeModelMenuBar.app`.
- [ ] Clear app xattrs, verify codesign, and verify `lipo` reports `arm64` and `x86_64`.
