import Foundation

/// Auth 层对外门面。
/// 责任：
///   - 维护账号元数据（账号名、provider 关联、备注）
///   - 把 AuthCredential 加密存到 Keychain
///   - 把"激活账号"对应的凭据同步落盘到 `~/.codex/auth.json`
///   - 暴露 OAuth device flow 入口
public actor AuthLayer {
    public struct Account: Codable, Equatable, Identifiable, Sendable {
        public var id: String
        public var label: String
        public var providerID: String?
        public var createdAt: Date

        public init(
            id: String = UUID().uuidString,
            label: String,
            providerID: String? = nil,
            createdAt: Date = Date()
        ) {
            self.id = id
            self.label = label
            self.providerID = providerID
            self.createdAt = createdAt
        }
    }

    public struct State: Codable, Equatable, Sendable {
        public var accounts: [Account]
        public var activeAccountID: String?

        public init(accounts: [Account] = [], activeAccountID: String? = nil) {
            self.accounts = accounts
            self.activeAccountID = activeAccountID
        }
    }

    private let keychain: KeychainStore
    private let authJSON: AuthJSONStore
    private let stateStore: StateStore
    private let oauth: OAuthDeviceFlow

    public init(
        keychain: KeychainStore = KeychainStore(),
        authJSON: AuthJSONStore = AuthJSONStore.defaultLocation(),
        stateStore: StateStore = StateStore(),
        oauth: OAuthDeviceFlow = OAuthDeviceFlow()
    ) {
        self.keychain = keychain
        self.authJSON = authJSON
        self.stateStore = stateStore
        self.oauth = oauth
    }

    public func currentState() throws -> State {
        try stateStore.load()
    }

    @discardableResult
    public func upsertAccount(
        label: String,
        credential: AuthCredential,
        providerID: String? = nil
    ) async throws -> Account {
        var state = try stateStore.load()
        // 复用同 label 的账号
        let account: Account
        if let idx = state.accounts.firstIndex(where: { $0.label == label }) {
            var existing = state.accounts[idx]
            existing.providerID = providerID ?? existing.providerID
            state.accounts[idx] = existing
            account = existing
        } else {
            let new = Account(label: label, providerID: providerID)
            state.accounts.append(new)
            account = new
        }
        try keychain.save(credential, account: account.id)
        try stateStore.save(state)
        return account
    }

    public func deleteAccount(id: String) async throws {
        var state = try stateStore.load()
        state.accounts.removeAll { $0.id == id }
        if state.activeAccountID == id {
            state.activeAccountID = nil
            try? authJSON.clear()
        }
        try keychain.delete(account: id)
        try stateStore.save(state)
    }

    public func credential(for id: String) async throws -> AuthCredential? {
        try keychain.load(account: id)
    }

    /// 切换激活账号。
    /// 行为：把对应 Keychain 中的凭据写到 `~/.codex/auth.json`。
    /// 之后 Codex 桌面端会监听该文件变更并自动生效（无需重启进程）。
    public func activateAccount(id: String) async throws {
        var state = try stateStore.load()
        guard state.accounts.contains(where: { $0.id == id }) else {
            throw AuthError.accountNotFound(id)
        }
        guard let credential = try keychain.load(account: id) else {
            throw AuthError.credentialMissing(id)
        }
        try authJSON.save(credential)
        state.activeAccountID = id
        try stateStore.save(state)
    }

    public func clearActive() async throws {
        var state = try stateStore.load()
        state.activeAccountID = nil
        try stateStore.save(state)
        try authJSON.clear()
    }

    /// 触发 OpenAI device code 流程。用户拿到 user_code 后去浏览器激活。
    /// 完成后会回写真实凭据并写入 `auth.json`。
    public func signInWithChatGPT(label: String) async throws -> Account {
        let token = try await oauth.runFullFlow()
        let credential = AuthCredential(
            mode: .chatgptOAuth,
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            idToken: token.idToken,
            email: token.email,
            accountId: token.accountId,
            expiresAt: Date().addingTimeInterval(TimeInterval(token.expiresIn)),
            lastRefresh: Date()
        )
        let account = try await upsertAccount(
            label: label,
            credential: credential,
            providerID: nil
        )
        try authJSON.save(credential)
        var state = try stateStore.load()
        state.activeAccountID = account.id
        try stateStore.save(state)
        return account
    }
}

public enum AuthError: Error, CustomStringConvertible {
    case accountNotFound(String)
    case credentialMissing(String)

    public var description: String {
        switch self {
        case .accountNotFound(let id): return "account not found: \(id)"
        case .credentialMissing(let id): return "credential missing for account: \(id)"
        }
    }
}

/// Auth 层的元数据（账号列表、激活账号 ID）持久化。
/// 落到 `~/Library/Application Support/CodexInjector/auth-state.json`，
/// 跟 `~/.codex/auth.json`（凭据）严格分离——元数据不污染 Codex 自己的配置目录。
public struct StateStore {
    public let fileURL: URL

    public init(fileURL: URL = StateStore.defaultLocation()) {
        self.fileURL = fileURL
    }

    public static func defaultLocation() -> URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("CodexInjector", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("auth-state.json")
    }

    public func load() throws -> AuthLayer.State {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            return AuthLayer.State()
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.iso8601.decode(AuthLayer.State.self, from: data)
    }

    public func save(_ state: AuthLayer.State) throws {
        let data = try JSONEncoder.iso8601.encode(state)
        try FileSystemSupport.atomicWrite(data: data, to: fileURL)
    }
}
