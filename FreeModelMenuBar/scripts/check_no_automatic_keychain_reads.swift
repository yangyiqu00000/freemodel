import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let balanceManagerURL = root
    .appendingPathComponent("FreeModelMenuBar")
    .appendingPathComponent("BalanceManager.swift")
let settingsViewURL = root
    .appendingPathComponent("FreeModelMenuBar")
    .appendingPathComponent("SettingsView.swift")

let balanceManager = try String(contentsOf: balanceManagerURL, encoding: .utf8)
let settingsView = try String(contentsOf: settingsViewURL, encoding: .utf8)

var failures: [String] = []

func reject(_ source: String, _ snippet: String, _ message: String) {
    if source.contains(snippet) {
        failures.append(message)
    }
}

reject(
    balanceManager,
    "hasDashboardCookies || (apiKey",
    "isConfigured must not read apiKey from Keychain on launch"
)

reject(
    balanceManager,
    "if let apiKey, !apiKey.isEmpty",
    "dashboard login failure path must not read apiKey from Keychain"
)

reject(
    settingsView,
    "apiKeyInput = balanceManager.apiKey",
    "SettingsView.onAppear must not read apiKey from Keychain"
)

reject(
    settingsView,
    "if let currentKey = balanceManager.apiKey",
    "SettingsView must not display saved API key by reading Keychain"
)

if failures.isEmpty {
    print("No automatic Keychain reads detected.")
} else {
    print("Automatic Keychain read check failed:")
    for failure in failures {
        print("- \(failure)")
    }
    exit(1)
}
