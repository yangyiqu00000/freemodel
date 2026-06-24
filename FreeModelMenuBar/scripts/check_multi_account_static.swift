import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let balanceManagerURL = root
    .appendingPathComponent("FreeModelMenuBar")
    .appendingPathComponent("FreeModelMenuBar")
    .appendingPathComponent("BalanceManager.swift")
let webLoginURL = root
    .appendingPathComponent("FreeModelMenuBar")
    .appendingPathComponent("FreeModelMenuBar")
    .appendingPathComponent("FreeModelWebLoginWindowController.swift")

let balanceManager = try String(contentsOf: balanceManagerURL, encoding: .utf8)
let webLogin = try String(contentsOf: webLoginURL, encoding: .utf8)

var failures: [String] = []

func require(_ source: String, _ snippet: String, _ message: String) {
    if !source.contains(snippet) {
        failures.append(message)
    }
}

func reject(_ source: String, _ snippet: String, _ message: String) {
    if source.contains(snippet) {
        failures.append(message)
    }
}

require(
    balanceManager,
    "private let accountManager: AccountManager",
    "BalanceManager should depend on AccountManager"
)

require(
    balanceManager,
    "request.setValue(account.cookieHeader, forHTTPHeaderField: \"Cookie\")",
    "dashboard requests should send the active account cookie header"
)

require(
    balanceManager,
    "accountManager.updateBalance(result, for: account.id)",
    "successful refresh should persist balance onto the active account"
)

reject(
    balanceManager,
    "HTTPCookieStorage.shared.cookies",
    "BalanceManager should not inspect global shared cookies"
)

reject(
    balanceManager,
    "configuration.httpCookieStorage = .shared",
    "BalanceManager should not use shared cookie storage for dashboard requests"
)

require(
    webLogin,
    "WKWebsiteDataStore.nonPersistent()",
    "login window should use an isolated non-persistent WebKit data store"
)

if failures.isEmpty {
    print("multi-account-static-check-pass")
} else {
    print("multi-account-static-check-fail:")
    for failure in failures {
        print("- \(failure)")
    }
    exit(1)
}
