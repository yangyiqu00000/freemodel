import Foundation
import Combine

/// 一条注入配置。把"激活时希望写入 ~/.codex/auth.json + config.toml 的内容"完整存下来。
public struct InjectionConfiguration: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case official
        case thirdParty
    }
    public var id: String
    public var label: String
    public var kind: Kind
    public var providerID: String
    public var authJSON: String
    public var configTOML: String
    public var createdAt: Date
    public var updatedAt: Date
    public init(
        id: String = UUID().uuidString,
        label: String,
        kind: Kind,
        providerID: String = "",
        authJSON: String = "",
        configTOML: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.label = label
        self.kind = kind
        self.providerID = providerID
        self.authJSON = authJSON
        self.configTOML = configTOML
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ActiveInjectionInfo: Codable, Equatable, Sendable {
    public var configurationID: String
    public var activatedAt: Date
    public init(configurationID: String, activatedAt: Date = Date()) {
        self.configurationID = configurationID
        self.activatedAt = activatedAt
    }
}

public struct InjectionConfigStore {
    public struct Snapshot: Codable, Equatable, Sendable {
        public var configurations: [InjectionConfiguration]
        public var activeConfigurationID: String?
        public var activeActivatedAt: Date?
        public init(
            configurations: [InjectionConfiguration] = [],
            activeConfigurationID: String? = nil,
            activeActivatedAt: Date? = nil
        ) {
            self.configurations = configurations
            self.activeConfigurationID = activeConfigurationID
            self.activeActivatedAt = activeActivatedAt
        }
    }
    public let fileURL: URL
    public init(fileURL: URL = InjectionConfigStore.defaultLocation()) {
        self.fileURL = fileURL
    }
    public static func defaultLocation() -> URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("CodexInjector", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("injection-configs.json")
    }
    public func load() throws -> Snapshot {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return Snapshot() }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.iso8601.decode(Snapshot.self, from: data)
    }
    public func save(_ snapshot: Snapshot) throws {
        let data = try JSONEncoder.iso8601.encode(snapshot)
        try FileSystemSupport.atomicWrite(data: data, to: fileURL)
    }
}

@MainActor
public final class AppLayer: ObservableObject {
    public static let shared = AppLayer()

    private let auth: AuthLayer
    let provider: ProviderLayer
    private let config: ConfigLayer
    private let injectionStore: InjectionConfigStore
    private let codexHome: URL

    @Published public private(set) var authState: AuthLayer.State = AuthLayer.State()
    @Published public private(set) var providerCatalog: ProviderCatalogStore.Catalog = ProviderCatalogStore.Catalog()
    @Published public private(set) var configSnapshot: ConfigLayer.Snapshot = ConfigLayer.Snapshot()
    @Published public private(set) var lastError: String?
    @Published public private(set) var lastSuccessMessage: String?
    @Published public private(set) var injectionConfigurations: [InjectionConfiguration] = []
    @Published public private(set) var activeInjection: ActiveInjectionInfo?

    public init(
        auth: AuthLayer? = nil,
        provider: ProviderLayer = ProviderLayer(),
        config: ConfigLayer? = nil,
        injectionStore: InjectionConfigStore = InjectionConfigStore(),
        codexHome: URL? = nil
    ) {
        let home = codexHome ?? CodexHomeLocator.resolve()
        self.codexHome = home
        self.auth = auth ?? AuthLayer(authJSON: AuthJSONStore(fileURL: home.appendingPathComponent("auth.json")))
        self.provider = provider
        self.config = config ?? ConfigLayer(
            file: CodexConfigFile(fileURL: home.appendingPathComponent("config.toml")),
            providerLayer: provider
        )
        self.injectionStore = injectionStore
        if let stored = try? injectionStore.load() {
            self.injectionConfigurations = stored.configurations
            self.activeInjection = stored.activeConfigurationID.flatMap { id in
                ActiveInjectionInfo(configurationID: id, activatedAt: stored.activeActivatedAt ?? Date())
            }
        }
    }

    public func bootstrap() {
        Task { await refresh() }
    }

    public func refresh() async {
        // 三路 IO 互不依赖，async let 并发比串行 await 快（本地文件读在小机器上也能省下几十毫秒）。
        // config 路径保持原「失败回退到空 Snapshot」语义，单独一个 task 包裹 try?。
        do {
            async let stateTask = auth.currentState()
            async let catalogTask = provider.currentCatalog()
            async let snapTask: ConfigLayer.Snapshot = {
                (try? await config.currentSnapshot()) ?? ConfigLayer.Snapshot()
            }()
            let (state, catalog, snapshot) = try await (stateTask, catalogTask, snapTask)
            await MainActor.run {
                self.authState = state
                self.providerCatalog = catalog
                self.configSnapshot = snapshot
            }
        } catch {
            await MainActor.run { self.lastError = "Refresh failed: \(error)" }
        }
    }

    // MARK: - 注入配置 CRUD

    public func addEmptyThirdPartyConfiguration(label: String, providerID: String) {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedProvider = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalLabel = trimmedLabel.isEmpty ? "第三方 \(Self.shortNow())" : trimmedLabel
        let finalProvider = trimmedProvider.isEmpty ? "custom-\(Self.shortNow())" : trimmedProvider
        let emptyAuth = "{\n  \n}"
        let emptyTOML = "# 在此编辑 config.toml 完整内容。\n# 激活时会原子写入 ~/.codex/config.toml。\n\n"
        let cfg = InjectionConfiguration(
            label: finalLabel,
            kind: .thirdParty,
            providerID: finalProvider,
            authJSON: emptyAuth,
            configTOML: emptyTOML
        )
        injectionConfigurations.append(cfg)
        persistInjectionState()
        lastSuccessMessage = "已新增第三方配置：\(cfg.label)"
        lastError = nil
    }

    public func addOfficialConfigurationViaSignIn(label: String) async {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalLabel = trimmedLabel.isEmpty ? "官方 ChatGPT \(Self.shortNow())" : trimmedLabel
        do {
            let account = try await auth.signInWithChatGPT(label: finalLabel)
            let authJSON = (try? readCurrentAuthJSONText()) ?? "{}"
            let snapshot = (try? await config.currentSnapshot()) ?? ConfigLayer.Snapshot()
            let configTOML = composeOfficialConfigTOML(snapshot: snapshot)
            let cfg = InjectionConfiguration(
                label: finalLabel,
                kind: .official,
                providerID: "openai",
                authJSON: authJSON,
                configTOML: configTOML
            )
            injectionConfigurations.append(cfg)
            persistInjectionState()
            await refresh()
            lastSuccessMessage = "已新增官方配置：\(account.label)"
            lastError = nil
        } catch {
            lastError = "官方登录失败：\(error)"
        }
    }

    public func prepareOfficialLoginSession(label: String) {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalLabel = trimmedLabel.isEmpty ? "官方 ChatGPT \(Self.shortNow())" : trimmedLabel
        do {
            let authURL = codexHome.appendingPathComponent("auth.json")
            let fm = FileManager.default
            if fm.fileExists(atPath: authURL.path) {
                try fm.removeItem(at: authURL)
            }
            let cfg = InjectionConfiguration(
                label: finalLabel,
                kind: .official,
                providerID: "openai",
                authJSON: "{\n  \n}",
                configTOML: "# 走 OpenAI 官方路由：不需要 model_provider 字段。\n# 在此仅保留你希望保留的非注入配置。\n"
            )
            injectionConfigurations.append(cfg)
            persistInjectionState()
            lastSuccessMessage = "已新增官方配置。请在终端跑 `codex` 完成 ChatGPT 登录，登录后回到此界面点 '保存当前 ~/.codex'。"
            lastError = nil
        } catch {
            lastError = "准备官方登录失败：\(error)"
        }
    }

    public func captureCurrentCodexState(into configurationID: String) {
        guard let idx = injectionConfigurations.firstIndex(where: { $0.id == configurationID }) else {
            lastError = "未找到该配置"
            return
        }
        let authText = (try? readCurrentAuthJSONText()) ?? injectionConfigurations[idx].authJSON
        let tomlText = (try? readCurrentConfigTOMLText()) ?? injectionConfigurations[idx].configTOML
        injectionConfigurations[idx].authJSON = authText
        injectionConfigurations[idx].configTOML = tomlText
        injectionConfigurations[idx].updatedAt = Date()
        persistInjectionState()
        lastSuccessMessage = "已把当前 ~/.codex 状态保存到：\(injectionConfigurations[idx].label)"
        lastError = nil
    }

    public func updateConfiguration(_ updated: InjectionConfiguration) {
        guard let idx = injectionConfigurations.firstIndex(where: { $0.id == updated.id }) else { return }
        var copy = updated
        copy.updatedAt = Date()
        injectionConfigurations[idx] = copy
        persistInjectionState()
    }

    public func deleteConfiguration(id: String) {
        injectionConfigurations.removeAll { $0.id == id }
        if activeInjection?.configurationID == id {
            activeInjection = nil
        }
        persistInjectionState()
    }

    public func activateConfiguration(id: String) {
        guard let cfg = injectionConfigurations.first(where: { $0.id == id }) else {
            lastError = "未找到该配置"
            return
        }
        do {
            try writeAuthJSON(cfg.authJSON)
            try writeConfigTOML(cfg.configTOML)
            activeInjection = ActiveInjectionInfo(configurationID: id)
            persistInjectionState()
            Task { await refresh() }
            lastSuccessMessage = "已激活：\(cfg.label)"
            lastError = nil
        } catch {
            lastError = "激活失败：\(error)"
        }
    }

    /// 停用当前激活的注入：把 Codex 目录恢复到"出厂状态"——直接删掉 auth.json 和 config.toml。
    /// 任何持久化的 activeInjection 也清掉，避免出现"UI 已激活但本地不存在"的不一致。
    public func deactivate() {
        do {
            try deleteCodexStateFiles()
            activeInjection = nil
            persistInjectionState()
            Task { await refresh() }
            lastSuccessMessage = "已停用注入（~/.codex/auth.json + config.toml 已删除）"
            lastError = nil
        } catch {
            lastError = "停用失败：\(error)"
        }
    }

    // MARK: - 旧 API（保留以兼容旧 UI/调用点，但不再触发 apply）

    public func signInWithChatGPT(label: String) async {
        await addOfficialConfigurationViaSignIn(label: label)
    }

    public func addAPIKeyAccount(label: String, apiKey: String, providerID: String? = nil) async {
        let finalLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalProvider = providerID ?? "custom"
        let authJSON = "{\n  \"OPENAI_API_KEY\": \"\(apiKey)\"\n}\n"
        let cfg = InjectionConfiguration(
            label: finalLabel.isEmpty ? "API Key \(Self.shortNow())" : finalLabel,
            kind: .thirdParty,
            providerID: finalProvider,
            authJSON: authJSON,
            configTOML: "model_provider = \"\(finalProvider)\"\n"
        )
        injectionConfigurations.append(cfg)
        persistInjectionState()
        lastSuccessMessage = "已新增配置：\(cfg.label)（未激活）"
        lastError = nil
    }

    public func activateAccount(id: String) async {
        activateConfiguration(id: id)
    }

    public func deleteAccount(id: String) {
        deleteConfiguration(id: id)
    }

    public func setActiveProvider(id: String) async {
        if let active = activeInjection,
           let idx = injectionConfigurations.firstIndex(where: { $0.id == active.configurationID }) {
            injectionConfigurations[idx].providerID = id
            injectionConfigurations[idx].updatedAt = Date()
            persistInjectionState()
        } else if let idx = injectionConfigurations.firstIndex(where: { $0.kind == .thirdParty }) {
            injectionConfigurations[idx].providerID = id
            injectionConfigurations[idx].updatedAt = Date()
            persistInjectionState()
        }
    }

    public func reapply() async {
        if let active = activeInjection {
            activateConfiguration(id: active.configurationID)
        } else {
            lastError = "当前没有激活的注入配置"
        }
    }

    public func detach() async {
        deactivate()
    }

    public func clearMessages() {
        lastError = nil
        lastSuccessMessage = nil
    }

    // MARK: - 私有辅助

    private func persistInjectionState() {
        var snap = InjectionConfigStore.Snapshot()
        snap.configurations = injectionConfigurations
        snap.activeConfigurationID = activeInjection?.configurationID
        snap.activeActivatedAt = activeInjection?.activatedAt
        do {
            try injectionStore.save(snap)
        } catch {
            lastError = "持久化注入配置失败：\(error)"
        }
    }

    private func readCurrentAuthJSONText() throws -> String {
        let url = codexHome.appendingPathComponent("auth.json")
        if !FileManager.default.fileExists(atPath: url.path) { return "{\n  \n}" }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func readCurrentConfigTOMLText() throws -> String {
        let url = codexHome.appendingPathComponent("config.toml")
        if !FileManager.default.fileExists(atPath: url.path) { return "" }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func writeAuthJSON(_ text: String) throws {
        let url = codexHome.appendingPathComponent("auth.json")
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        let data = Data(text.utf8)
        try FileSystemSupport.atomicWrite(data: data, to: url)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func writeConfigTOML(_ text: String) throws {
        let url = codexHome.appendingPathComponent("config.toml")
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        let data = Data(text.utf8)
        try FileSystemSupport.atomicWrite(data: data, to: url)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// 直接删除 ~/codexHome/auth.json 和 config.toml。两个文件都不存在了。
    /// 注意：哪怕当前没有 activeInjection，也允许调用——用户可能想"恢复出厂"。
    private func deleteCodexStateFiles() throws {
        let fm = FileManager.default
        let authURL = codexHome.appendingPathComponent("auth.json")
        let configURL = codexHome.appendingPathComponent("config.toml")
        var firstError: Error?
        for url in [authURL, configURL] {
            if fm.fileExists(atPath: url.path) {
                do {
                    try fm.removeItem(at: url)
                } catch {
                    if firstError == nil { firstError = error }
                }
            }
        }
        if let firstError { throw firstError }
    }

    private func composeOfficialConfigTOML(snapshot: ConfigLayer.Snapshot) -> String {
        var lines: [String] = []
        lines.append("# Codex 官方 ChatGPT OAuth 注入")
        lines.append("# 激活时不写 model_provider：让 Codex 走 OpenAI 官方路由。")
        if let model = snapshot.model, !model.isEmpty {
            lines.append("model = \"\(model)\"")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // DateFormatter 自 macOS 10.9 起线程安全，可作为 static let 复用避免每次新建。
    private static let shortNowFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMdd-HHmm"
        return f
    }()

    private static func shortNow() -> String {
        Self.shortNowFormatter.string(from: Date())
    }
}
