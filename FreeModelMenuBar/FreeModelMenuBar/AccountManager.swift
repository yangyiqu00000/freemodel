//
//  AccountManager.swift
//  FreeModelMenuBar
//
//  Multi-account state, persistence, and dashboard cookie isolation.
//

import Combine
import Foundation



struct RouterSettings: Codable, Equatable {
    var enabled: Bool
    var port: Int
    var upstreamBaseURL: String
    var routeModel: String
    var defaultModel: String
    var supportsStreaming: Bool
    var maxConcurrency: Int?
    var minIntervalMs: Int?
    var failoverEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case enabled, port, upstreamBaseURL, routeModel, defaultModel, supportsStreaming, maxConcurrency, minIntervalMs, failoverEnabled
    }

    init(
        enabled: Bool,
        port: Int,
        upstreamBaseURL: String,
        routeModel: String,
        defaultModel: String,
        supportsStreaming: Bool,
        maxConcurrency: Int? = 0,
        minIntervalMs: Int? = 0,
        failoverEnabled: Bool? = true
    ) {
        self.enabled = enabled
        self.port = port
        self.upstreamBaseURL = upstreamBaseURL
        self.routeModel = routeModel
        self.defaultModel = defaultModel
        self.supportsStreaming = supportsStreaming
        self.maxConcurrency = maxConcurrency
        self.minIntervalMs = minIntervalMs
        self.failoverEnabled = failoverEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        port = try container.decode(Int.self, forKey: .port)
        upstreamBaseURL = try container.decode(String.self, forKey: .upstreamBaseURL)
        routeModel = try container.decode(String.self, forKey: .routeModel)
        defaultModel = try container.decode(String.self, forKey: .defaultModel)
        supportsStreaming = try container.decode(Bool.self, forKey: .supportsStreaming)
        maxConcurrency = try container.decodeIfPresent(Int.self, forKey: .maxConcurrency) ?? 0
        minIntervalMs = try container.decodeIfPresent(Int.self, forKey: .minIntervalMs) ?? 0
        failoverEnabled = try container.decodeIfPresent(Bool.self, forKey: .failoverEnabled) ?? true
    }

    var isFailoverEnabled: Bool {
        failoverEnabled ?? true
    }
}


/// 4 个 provider 的全部元数据。新增 / 删除 provider 改这里 1 处即可。
struct ProviderSpec {
    let providerID: String
    let apiBaseURL: String
    let dashboardURL: String
    let queryMode: QueryMode
    let upstreamBaseURL: String      // router 默认上游
    let defaultModel: String          // router 默认 model
    let routeModel: String            // router 默认 route model
    let docURL: String                // 文档链接
    let displayNamePrefix: String     // 账号默认名 / 显示名

    static let all: [String: ProviderSpec] = [
        "freemodel": ProviderSpec(
            providerID: "freemodel",
            apiBaseURL: "https://api.freemodel.dev",
            dashboardURL: "https://freemodel.dev",
            queryMode: .dashboard,
            upstreamBaseURL: "https://api.freemodel.dev/v1/chat/completions",
            defaultModel: "codex-mini",
            routeModel: "codex-mini",
            docURL: "https://freemodel.dev/docs",
            displayNamePrefix: "FreeModel"
        ),
        "deepseek": ProviderSpec(
            providerID: "deepseek",
            apiBaseURL: "https://api.deepseek.com",
            dashboardURL: "https://platform.deepseek.com",
            queryMode: .apiKey,
            upstreamBaseURL: "https://api.deepseek.com/v1/chat/completions",
            defaultModel: "deepseek-chat",
            routeModel: "codex-mini",
            docURL: "https://api-docs.deepseek.com",
            displayNamePrefix: "DeepSeek"
        ),
        "openrouter": ProviderSpec(
            providerID: "openrouter",
            apiBaseURL: "https://openrouter.ai/api/v1",
            dashboardURL: "https://openrouter.ai",
            queryMode: .apiKey,
            upstreamBaseURL: "https://openrouter.ai/api/v1/chat/completions",
            defaultModel: "deepseek/deepseek-v4-flash:free",
            routeModel: "codex-mini",
            docURL: "https://openrouter.ai/docs",
            displayNamePrefix: "OpenRouter"
        ),
        "modelscope": ProviderSpec(
            providerID: "modelscope",
            apiBaseURL: "https://api-inference.modelscope.cn",
            dashboardURL: "https://modelscope.cn",
            queryMode: .apiKey,
            upstreamBaseURL: "https://api-inference.modelscope.cn/v1/chat/completions",
            defaultModel: "ZhipuAI/GLM-5.1",
            routeModel: "codex-mini",
            docURL: "https://modelscope.cn/docs/model-service/API-Inference/api-provider",
            displayNamePrefix: "ModelScope"
        ),
    ]

    /// 不区分大小写查表；找不到返回 freemodel 默认
    static func preset(for id: String) -> ProviderSpec {
        all[id.lowercased()] ?? all["freemodel"]!
    }
}



struct ProviderAccount: Codable, Equatable, Identifiable {
    let id: UUID
    var providerID: String
    var displayName: String
    var apiBaseURL: String
    var dashboardURL: String
    var cookieRecords: [StoredCookie]
    var apiKeyKeychainID: String
    var hasAPIKey: Bool
    var lastBalance: BalanceInfo?
    var lastRefreshDate: Date?
    var createdAt: Date
    var updatedAt: Date
    var queryMode: QueryMode
    var refreshInterval: TimeInterval
    var apiKey: String?
    var routerSettings: RouterSettings?

    init(
        id: UUID = UUID(),
        providerID: String = "freemodel",
        displayName: String,
        apiBaseURL: String = "https://api.freemodel.dev",
        dashboardURL: String = "https://freemodel.dev",
        cookieRecords: [StoredCookie] = [],
        apiKeyKeychainID: String? = nil,
        hasAPIKey: Bool = false,
        lastBalance: BalanceInfo? = nil,
        lastRefreshDate: Date? = nil,
        queryMode: QueryMode = .dashboard,
        refreshInterval: TimeInterval = 300,
        apiKey: String? = nil,
        routerSettings: RouterSettings? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.providerID = providerID
        self.displayName = displayName
        self.apiBaseURL = apiBaseURL
        self.dashboardURL = dashboardURL
        self.cookieRecords = cookieRecords
        self.apiKeyKeychainID = apiKeyKeychainID ?? "freemodel_api_key_\(id.uuidString)"
        self.hasAPIKey = hasAPIKey
        self.lastBalance = lastBalance
        self.lastRefreshDate = lastRefreshDate
        self.queryMode = queryMode
        self.refreshInterval = refreshInterval
        self.apiKey = apiKey
        self.routerSettings = routerSettings
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, providerID, displayName, apiBaseURL, dashboardURL, cookieRecords, apiKeyKeychainID, hasAPIKey, lastBalance, lastRefreshDate, queryMode, refreshInterval, apiKey, routerSettings, createdAt, updatedAt
    }

    /// 编码时使用的 keys（排除 apiKey — 它走 Keychain，不落在 UserDefaults 里）
    private enum EncodingKeys: String, CodingKey {
        case id, providerID, displayName, apiBaseURL, dashboardURL, cookieRecords, apiKeyKeychainID, hasAPIKey, lastBalance, lastRefreshDate, queryMode, refreshInterval, routerSettings, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        providerID = try container.decode(String.self, forKey: .providerID)
        displayName = try container.decode(String.self, forKey: .displayName)
        apiBaseURL = try container.decode(String.self, forKey: .apiBaseURL)
        dashboardURL = try container.decode(String.self, forKey: .dashboardURL)
        cookieRecords = try container.decode([StoredCookie].self, forKey: .cookieRecords)
        apiKeyKeychainID = try container.decode(String.self, forKey: .apiKeyKeychainID)
        hasAPIKey = try container.decode(Bool.self, forKey: .hasAPIKey)
        lastBalance = try container.decodeIfPresent(BalanceInfo.self, forKey: .lastBalance)
        lastRefreshDate = try container.decodeIfPresent(Date.self, forKey: .lastRefreshDate)
        queryMode = try container.decodeIfPresent(QueryMode.self, forKey: .queryMode) ?? .dashboard
        refreshInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .refreshInterval) ?? 300
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey)
        routerSettings = try container.decodeIfPresent(RouterSettings.self, forKey: .routerSettings)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: EncodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(providerID, forKey: .providerID)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(apiBaseURL, forKey: .apiBaseURL)
        try container.encode(dashboardURL, forKey: .dashboardURL)
        try container.encode(cookieRecords, forKey: .cookieRecords)
        try container.encode(apiKeyKeychainID, forKey: .apiKeyKeychainID)
        try container.encode(hasAPIKey, forKey: .hasAPIKey)
        try container.encodeIfPresent(lastBalance, forKey: .lastBalance)
        try container.encodeIfPresent(lastRefreshDate, forKey: .lastRefreshDate)
        try container.encode(queryMode, forKey: .queryMode)
        try container.encode(refreshInterval, forKey: .refreshInterval)
        try container.encodeIfPresent(routerSettings, forKey: .routerSettings)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    /// 从旧数据解码后，清理内存中的 apiKey（已迁移到 Keychain），避免反序列化时泄露。
    /// AccountManager.init 中会在加载后统一调用 migrateAPIKeysFromStorage()。
    /// 解码时保留 apiKey 是为了兼容旧版 UserDefaults 存储格式。

    var activeRouterSettings: RouterSettings {
        let upstreamURL: String
        let model: String

        let preset = ProviderSpec.preset(for: providerID)
        upstreamURL = preset.upstreamBaseURL
        model = preset.defaultModel

        return routerSettings ?? RouterSettings(
            enabled: false,
            port: 38440,
            upstreamBaseURL: upstreamURL,
            routeModel: preset.routeModel,
            defaultModel: model,
            supportsStreaming: true,
            failoverEnabled: true
        )
    }

    var validCookies: [StoredCookie] {
        cookieRecords.filter { !$0.isExpired }
    }

    var hasDashboardSession: Bool {
        !validCookies.isEmpty
    }

    var cookieHeader: String {
        // validCookies 是 computed property，直接连用会走两次 filter。
        // 局部缓存让一次过滤结果被 sort/map/join 复用。
        let valid = validCookies
        return valid
            .sorted { $0.name < $1.name }
            .map(\.headerPair)
            .joined(separator: "; ")
    }

    var displayProviderName: String {
        return ProviderSpec.preset(for: providerID).displayNamePrefix
    }

    var docURLString: String {
        let preset = ProviderSpec.preset(for: providerID)
        if preset.providerID == "freemodel" {
            return "\(dashboardURL)/docs"
        }
        return preset.docURL
    }
}

struct AccountState: Codable, Equatable {
    var accounts: [ProviderAccount]
    var activeAccountID: UUID?
}

protocol AccountStorage {
    func loadState() -> AccountState?
    func saveState(_ state: AccountState)
}

final class UserDefaultsAccountStorage: AccountStorage {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "freemodel.accounts.state.v1") {
        self.defaults = defaults
        self.key = key
    }

    func loadState() -> AccountState? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(AccountState.self, from: data)
    }

    func saveState(_ state: AccountState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }
}

final class InMemoryAccountStorage: AccountStorage {
    private var state: AccountState?

    func loadState() -> AccountState? {
        state
    }

    func saveState(_ state: AccountState) {
        self.state = state
    }
}

/// 线程安全的 API Key 内存缓存。
/// 避免 session 内重复触发 Keychain 弹窗（macOS 每次 SecItemCopyMatching 走 ACL 验证）。
private final class _APICache: @unchecked Sendable {
    private var storage: [String: String] = [:]
    private let lock = NSLock()
    func value(for key: String) -> String? { lock.withLock { storage[key] } }
    func set(_ value: String, for key: String) { lock.withLock { storage[key] = value } }
    @discardableResult
    func removeValue(for key: String) -> String? { lock.withLock { storage.removeValue(forKey: key) } }
    func clear() { lock.withLock { storage.removeAll() } }
}

/// 线程安全的布尔值（用于懒迁移的 once 语义）。
private final class AtomicBool: @unchecked Sendable {
    private var _value: Bool = false
    private let lock = NSLock()
    var value: Bool {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

/// 旧版账号状态（含明文 apiKey），用于离线迁移。
private struct _LegacyAccount: Codable {
    var id: UUID
    var apiKey: String?
}

private struct _LegacyAccountState: Codable {
    var accounts: [_LegacyAccount]
}


@MainActor
final class AccountManager: ObservableObject {
    @Published private(set) var accounts: [ProviderAccount]
    @Published private(set) var activeAccountID: UUID?

    private let storage: AccountStorage
    private nonisolated(unsafe) static let appKeychainStore = AppKeychainStore()
    /// API Key 内存缓存（session 级），避免重复触发 Keychain 弹窗。
    private var apiKeyCache: [String: String] = [:]
    /// 标记旧数据迁移是否已完成。
    private var didMigrateAPIKeys = false

        init(storage: AccountStorage = UserDefaultsAccountStorage(), autoCreateDefaultAccount: Bool = true) {
        self.storage = storage

        if let state = storage.loadState() {
            self.accounts = state.accounts
            self.activeAccountID = state.activeAccountID
        } else {
            self.accounts = []
            self.activeAccountID = nil
        }


        if accounts.isEmpty && autoCreateDefaultAccount {
            let account = ProviderAccount(displayName: "FreeModel 1")
            accounts = [account]
            activeAccountID = account.id
            persist()
        } else if let activeAccountID, !accounts.contains(where: { $0.id == activeAccountID }) {
            self.activeAccountID = accounts.first?.id
            persist()
        } else if activeAccountID == nil {
            activeAccountID = accounts.first?.id
            persist()
        }

        // 迁移旧版 UserDefaults 中存储的 API Key 到 Keychain
        migrateAPIKeysFromStorage()
    }

    var activeAccount: ProviderAccount? {
        guard let activeAccountID else { return nil }
        return account(id: activeAccountID)
    }

    func account(id: UUID) -> ProviderAccount? {
        accounts.first { $0.id == id }
    }

    @discardableResult
    func createAccount(displayName: String? = nil, providerID: String = "freemodel") -> ProviderAccount {
        let apiURL: String
        let dashURL: String
        let mode: QueryMode

        let preset = ProviderSpec.preset(for: providerID)
        apiURL = preset.apiBaseURL
        dashURL = preset.dashboardURL
        mode = preset.queryMode

        let account = ProviderAccount(
            providerID: providerID,
            displayName: displayName ?? nextDefaultAccountName(providerID: providerID),
            apiBaseURL: apiURL,
            dashboardURL: dashURL,
            queryMode: mode
        )
        accounts.append(account)
        activeAccountID = account.id
        persist()
        return account
    }

    func selectAccount(id: UUID) {
        guard accounts.contains(where: { $0.id == id }) else { return }
        activeAccountID = id
        persist()
    }

    func moveAccount(fromOffsets source: IndexSet, toOffset destination: Int) {
        // 手动实现（替代 SwiftUI 的 move(fromOffsets:toOffset:)），避免 CLI 测试时依赖 SwiftUI
        let sortedIndices = source.sorted()
        let movedItems = sortedIndices.map { accounts[$0] }
        for index in sortedIndices.reversed() {
            accounts.remove(at: index)
        }
        let insertAt: Int
        if let first = sortedIndices.first, destination > first {
            insertAt = destination - movedItems.count
        } else {
            insertAt = destination
        }
        for (offset, item) in movedItems.enumerated() {
            accounts.insert(item, at: insertAt + offset)
        }
        persist()
    }


    func renameAccount(id: UUID, displayName: String) {
        let cleaned = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        updateAccount(id: id) { account in
            account.displayName = cleaned
        }
    }

    @discardableResult
    func deleteAccount(id: UUID) -> ProviderAccount? {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = accounts.remove(at: index)
        // 同时清理 Keychain 中的 API Key
        try? Self.appKeychainStore.delete(account: removed.apiKeyKeychainID)
        if activeAccountID == id {
            activeAccountID = accounts.first?.id
        }
        persist()
        return removed
    }

    func updateCookies(_ cookies: [StoredCookie], for id: UUID) {
        updateAccount(id: id) { account in
            account.cookieRecords = cookies
        }
    }

    func updateCookies(from cookies: [HTTPCookie], for id: UUID, domainContains domain: String = "freemodel.dev") {
        let records = cookies
            .filter { $0.domain.contains(domain) }
            .map(StoredCookie.init(cookie:))
        updateCookies(records, for: id)
    }

    func clearCookies(for id: UUID) {
        updateCookies([], for: id)
    }

    func updateBalance(_ balance: BalanceInfo, for id: UUID) {
        updateAccount(id: id) { account in
            account.lastBalance = balance
            account.lastRefreshDate = balance.lastUpdated
        }
    }

    func clearBalance(for id: UUID) {
        updateAccount(id: id) { account in
            account.lastBalance = nil
            account.lastRefreshDate = nil
        }
    }

    func setAPIKeyConfigured(_ configured: Bool, for id: UUID) {
        updateAccount(id: id) { account in
            account.hasAPIKey = configured
        }
    }

    func updateURLs(apiURL: String, dashboardURL: String, for id: UUID) {
        updateAccount(id: id) { account in
            let cleanedAPIURL = apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanedDashboardURL = dashboardURL.trimmingCharacters(in: .whitespacesAndNewlines)
            account.apiBaseURL = cleanedAPIURL
            account.dashboardURL = cleanedDashboardURL
            if cleanedAPIURL.lowercased().contains("deepseek") {
                account.providerID = "deepseek"
            } else if cleanedAPIURL.lowercased().contains("freemodel") {
                account.providerID = "freemodel"
            }
        }
    }

    func updateQueryMode(_ mode: QueryMode, for id: UUID) {
        updateAccount(id: id) { account in
            account.queryMode = mode
        }
    }

    func updateRefreshInterval(_ interval: TimeInterval, for id: UUID) {
        updateAccount(id: id) { account in
            account.refreshInterval = interval
        }
    }

    func updateAPIKey(_ key: String?, for id: UUID) {
        let keychainID = apiKeyStorageKey(for: id) ?? "freemodel_api_key_\(id.uuidString)"
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed?.isEmpty ?? true {
            // 清除 Keychain 中的 API Key
            try? Self.appKeychainStore.delete(account: keychainID)
            setAPIKeyConfigured(false, for: id)
        } else {
            // 写入 Keychain
            do {
                try Self.appKeychainStore.save(apiKey: trimmed!, account: keychainID)
                setAPIKeyConfigured(true, for: id)
            } catch {
                print("Keychain save failed: \(error)")
            }
        }
    }

    /// 从 Keychain 读取指定账号的 API Key。
    /// 返回 nil = 未配置或读取失败。
    /// 设计要点：
    ///   - 内存缓存（apiKeyCache）避免 session 内重复触发 Keychain 弹窗
    ///   - 懒迁移确保旧版 UserDefaults 数据也被迁移
    ///   - 非 isolated，允许 RouterManager（非 MainActor）直接调用
    nonisolated func resolveAPIKey(for id: UUID) -> String? {
        let keychainID = "freemodel_api_key_\(id.uuidString)"

        // 1. 查缓存
        if let cached = Self._apiKeyCache.value(for: keychainID) {
            return cached
        }

        // 2. 懒迁移（仅首次触发）
        Self._ensureMigrated()

        // 3. 读 Keychain
        guard let key = try? Self.appKeychainStore.load(account: keychainID) else {
            return nil
        }

        // 4. 写缓存
        Self._apiKeyCache.set(key, for: keychainID)
        return key
    }

    // MARK: - API Key 内存缓存
    private nonisolated(unsafe) static let _apiKeyCache: _APICache = _APICache()
    private nonisolated(unsafe) static let _lazyMigrated: AtomicBool = AtomicBool()

    /// 懒迁移触发器：仅在首次调用 resolveAPIKey 时执行一次。
    /// 通过 dispatch_once 语义 + MainActor 异步执行，避免 init 时触 Keychain 弹窗。
    private nonisolated static func _ensureMigrated() {
        guard !_lazyMigrated.value else { return }
        _lazyMigrated.value = true
        DispatchQueue.main.async {
            // 通过共享实例（ObjectIdentifier 定位）触发迁移
            _migrateIfNeeded()
        }
    }

    /// 查找 AccountManager 实例并执行迁移。
    /// 不使用 @MainActor 约束，由 DispatchQueue.main.async 保证在主线程执行。
    private nonisolated static func _migrateIfNeeded() {
        // AccountManager 是 @MainActor 类，无法直接持有静态引用。
        // 通过 Objective-C runtime 或 Published 订阅查找不现实。
        // 简单方案：迁移逻辑只读 UserDefaults，不依赖实例状态。
        // 如果有旧数据，直接迁移；没有则跳过。
        _legacyDirectMigrate()
    }

    /// 直接读取 UserDefaults 旧数据并迁移到 Keychain（不依赖 AccountManager 实例）。
    /// 兼容旧版存储格式：accounts 数组中的 apiKey 字段。
    private nonisolated static func _legacyDirectMigrate() {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: "freemodel.accounts.state.v1"),
              let state = try? JSONDecoder().decode(_LegacyAccountState.self, from: data)
        else { return }

        let store = AppKeychainStore()
        for acct in state.accounts {
            guard let key = acct.apiKey, !key.isEmpty else { continue }
            let keychainID = "freemodel_api_key_\(acct.id.uuidString)"
            guard (try? store.load(account: keychainID)) == nil else { continue }
            try? store.save(apiKey: key, account: keychainID)
        }
    }

    func updateRouterSettings(_ settings: RouterSettings, for id: UUID) {
        updateAccount(id: id) { account in
            account.routerSettings = settings
        }
    }

    func apiKeyStorageKey(for id: UUID) -> String? {
        account(id: id)?.apiKeyKeychainID
    }

    private func updateAccount(id: UUID, mutate: (inout ProviderAccount) -> Void) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        mutate(&accounts[index])
        accounts[index].updatedAt = Date()
        persist()
    }

    private func nextDefaultAccountName(providerID: String = "freemodel") -> String {
        let prefix = ProviderSpec.preset(for: providerID).displayNamePrefix
        let existingCount = accounts.filter { $0.providerID == providerID }.count
        return "\(prefix) \(existingCount + 1)"
    }

    private func persist() {
        storage.saveState(AccountState(accounts: accounts, activeAccountID: activeAccountID))
    }

    /// 从 UserDefaults 解码的旧数据中提取 apiKey，迁移到 Keychain。
    /// 迁移后清除内存中的 apiKey，并重写存储（encode 时已排除 apiKey）。
    private func migrateAPIKeysFromStorage() {
        var needsRepersist = false
        for i in accounts.indices {
            guard let oldKey = accounts[i].apiKey, !oldKey.isEmpty else { continue }
            let keychainID = accounts[i].apiKeyKeychainID
            // 仅在 Keychain 中还不存在时写入
            if (try? Self.appKeychainStore.load(account: keychainID)) == nil {
                do {
                    try Self.appKeychainStore.save(apiKey: oldKey, account: keychainID)
                    accounts[i].hasAPIKey = true
                    print("Migrated API Key for \(accounts[i].displayName) to Keychain")
                } catch {
                    print("Failed to migrate API Key: \(error)")
                }
            }
            // 清理内存中的明文
            accounts[i].apiKey = nil
            needsRepersist = true
        }
        if needsRepersist {
            persist()
        }
    }
}
