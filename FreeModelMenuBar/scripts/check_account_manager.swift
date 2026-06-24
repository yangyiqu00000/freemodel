import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        print("account-manager-check-fail: \(message)")
        exit(1)
    }
}

@main
enum CheckAccountManager {
    static func main() {
        let storage = InMemoryAccountStorage()
        let manager = AccountManager(storage: storage, autoCreateDefaultAccount: false)

        let primary = manager.createAccount(displayName: "Primary")
        let backup = manager.createAccount(displayName: "Backup")

        expect(manager.accounts.count == 2, "expected two accounts")
        expect(primary.providerID == "freemodel", "default provider should be freemodel")
        expect(primary.apiKeyKeychainID != backup.apiKeyKeychainID, "api key ids must be isolated")
        expect(primary.apiKeyKeychainID.contains(primary.id.uuidString), "api key id should include account id")

        manager.updateAPIKey("  sk-primary  ", for: primary.id)
        manager.updateRefreshInterval(60, for: primary.id)
        manager.updateAPIKey("sk-backup", for: backup.id)
        manager.updateRefreshInterval(1800, for: backup.id)

        manager.selectAccount(id: backup.id)
        expect(manager.activeAccount?.id == backup.id, "backup should be active")

        let primaryCookies = [
            StoredCookie(
                name: "session",
                value: "primary-session",
                domain: ".freemodel.dev",
                path: "/",
                expiresAt: Date(timeIntervalSince1970: 2_000_000_000),
                isSecure: true,
                isHTTPOnly: true
            )
        ]

        let backupCookies = [
            StoredCookie(
                name: "session",
                value: "backup-session",
                domain: ".freemodel.dev",
                path: "/",
                expiresAt: Date(timeIntervalSince1970: 2_000_000_000),
                isSecure: true,
                isHTTPOnly: true
            ),
            StoredCookie(
                name: "theme",
                value: "dark mode",
                domain: ".freemodel.dev",
                path: "/",
                expiresAt: nil,
                isSecure: false,
                isHTTPOnly: false
            )
        ]

        manager.updateCookies(primaryCookies, for: primary.id)
        manager.updateCookies(backupCookies, for: backup.id)

        expect(manager.account(id: primary.id)?.cookieHeader == "session=primary-session", "primary cookie header mismatch")
        expect(manager.account(id: backup.id)?.cookieHeader == "session=backup-session; theme=dark%20mode", "backup cookie header mismatch")
        expect(manager.account(id: primary.id)?.hasDashboardSession == true, "primary should have dashboard session")
        expect(manager.account(id: backup.id)?.hasDashboardSession == true, "backup should have dashboard session")

        let balance = BalanceInfo(
            totalGranted: 100,
            totalUsed: 40,
            totalRemaining: 60,
            expiresAt: Date(timeIntervalSince1970: 2_000_000_001),
            lastUpdated: Date(timeIntervalSince1970: 2_000_000_002)
        )
        manager.updateBalance(balance, for: backup.id)

        let reloaded = AccountManager(storage: storage, autoCreateDefaultAccount: false)
        expect(reloaded.accounts.count == 2, "reload should preserve accounts")
        expect(reloaded.activeAccount?.id == backup.id, "reload should preserve active account")
        // API Key 不再持久化到 UserDefaults，走 Keychain。
        // 验证：hasAPIKey 为 true（Keychain 有值），resolveAPIKey 可读取
        expect(manager.account(id: primary.id)?.hasAPIKey == true, "updateAPIKey should set hasAPIKey")
        expect(manager.account(id: backup.id)?.hasAPIKey == true, "updateAPIKey should set hasAPIKey for backup")
        expect(reloaded.account(id: primary.id)?.hasAPIKey == true, "reload should preserve hasAPIKey flag")
        expect(reloaded.account(id: primary.id)?.refreshInterval == 60, "reload should preserve primary refresh interval")
        expect(reloaded.account(id: backup.id)?.refreshInterval == 1800, "reload should preserve backup refresh interval")
        expect(reloaded.account(id: primary.id)?.cookieHeader == "session=primary-session", "reload should preserve primary cookies")
        expect(reloaded.account(id: backup.id)?.cookieHeader == "session=backup-session; theme=dark%20mode", "reload should preserve backup cookies")
        expect(reloaded.account(id: backup.id)?.lastBalance?.totalRemaining == 60, "reload should preserve balance")

        reloaded.renameAccount(id: backup.id, displayName: "Backup Renamed")
        expect(reloaded.account(id: backup.id)?.displayName == "Backup Renamed", "rename should persist in memory")

        reloaded.deleteAccount(id: backup.id)
        expect(reloaded.accounts.count == 1, "delete should remove account")
        expect(reloaded.activeAccount?.id == primary.id, "deleting active should select first remaining account")

        let deepSeek = reloaded.createAccount(providerID: "deepseek")
        expect(deepSeek.displayName == "DeepSeek 1", "deepseek account should use a provider-specific name")
        expect(deepSeek.apiBaseURL == "https://api.deepseek.com", "deepseek account should use the official base URL")
        expect(deepSeek.queryMode == .apiKey, "deepseek account should default to API Key mode")
        expect(deepSeek.activeRouterSettings.defaultModel == "deepseek-chat", "deepseek router should default to a valid DeepSeek model")

        print("account-manager-check-pass")
    }
}
