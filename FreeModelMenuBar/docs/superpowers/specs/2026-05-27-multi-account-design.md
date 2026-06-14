# Multi Account Design

## Goal

Add complete multi-account management to the macOS menu bar app. The first provider is FreeModel, with each account able to store an isolated dashboard web session and an optional API key. The data model must leave room for future providers that may expose balance through API endpoints instead of a web dashboard.

## Current State

The app currently has one `BalanceManager` shared by the menu bar, settings window, and web login window. FreeModel dashboard balance is queried from `/api/usage`, `/api/billing`, and `/api/referral` using cookies copied from a single `WKWebView` login session. API keys are optional and are only used for model endpoint validation.

## Proposed Architecture

Introduce `ProviderAccount` records managed by a new `AccountManager`. Each account stores provider metadata, display name, dashboard cookies, last known balance, and a per-account keychain identifier for an optional API key. `BalanceManager` becomes the refresh coordinator for the active account instead of a global single-account state container.

FreeModel dashboard cookies are captured from a non-persistent `WKWebView` login window and stored on the selected account. Balance requests send the selected account's cookies in the request `Cookie` header, so multiple FreeModel accounts can be kept and refreshed without sharing a global cookie jar.

## Data Model

- `ProviderAccount`
  - `id`
  - `providerID`
  - `displayName`
  - `apiBaseURL`
  - `dashboardURL`
  - `cookieRecords`
  - `apiKeyKeychainID`
  - `hasAPIKey`
  - `lastBalance`
  - `lastRefreshDate`
  - `createdAt`
  - `updatedAt`
- `StoredCookie`
  - serializable cookie fields needed to build an HTTP `Cookie` header and restore a `WKHTTPCookieStore`
- `AccountManager`
  - loads/saves accounts in `UserDefaults`
  - tracks active account
  - creates, renames, deletes, and selects accounts
  - stores per-account cookies and last balance

## UI

The menu bar popover shows the active account and allows switching when multiple accounts exist. It displays balance for the active account and refreshes the active account only.

The settings window becomes an account manager. It includes an account list, add/delete/rename controls, login controls for the selected account, API key save/test/clear controls, and refresh interval settings.

## Error Handling

If the selected account has no valid cookies, balance refresh shows a login-required message scoped to that account. If cookies expire, only that account is marked as needing login. API key validation errors are scoped to the selected account. Deleting an account removes its stored API key and dashboard cookies.

## Keychain Behavior

The app must not read API keys on startup or when merely opening settings. API key reads happen only when the user explicitly tests a saved key or performs an API-key-specific action. This preserves the previous fix that avoids macOS keychain prompts on launch.

## Verification

Verification must cover account creation, active account switching, cookie isolation, persistence reload, API key metadata isolation, existing dashboard parsing, no automatic keychain reads, project file validity, Release build, app copying, code signing, and universal binary architecture.
