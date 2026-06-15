import Foundation

/// Config 层对外门面。
/// 责任：
///   - 加载/保存 `~/.codex/config.toml`
///   - 把 ProviderLayer 提供的 provider 注入到 `model_providers` 块
///   - 设置/取消 `model_provider`（激活的 provider id）
///   - 设置/取消 `model`（默认 model）
///   - 监听外部改动（其它进程写 config.toml 时的回放）
public actor ConfigLayer {
    public struct Snapshot: Equatable, Sendable {
        public var modelProvider: String?
        public var model: String?
        public var requiresOpenAIAuth: Bool?
        public var providers: [String]

        public init(
            modelProvider: String? = nil,
            model: String? = nil,
            requiresOpenAIAuth: Bool? = nil,
            providers: [String] = []
        ) {
            self.modelProvider = modelProvider
            self.model = model
            self.requiresOpenAIAuth = requiresOpenAIAuth
            self.providers = providers
        }
    }

    private let file: CodexConfigFile
    private let providerLayer: ProviderLayer
    private var watchSource: DispatchSourceFileSystemObject?

    public init(
        file: CodexConfigFile = .defaultLocation(),
        providerLayer: ProviderLayer
    ) {
        self.file = file
        self.providerLayer = providerLayer
    }

    public func currentSnapshot() throws -> Snapshot {
        let table = try file.loadTable()
        return Snapshot(
            modelProvider: table["model_provider"]?.stringValue,
            model: table["model"]?.stringValue,
            requiresOpenAIAuth: table["requires_openai_auth"]?.boolValue,
            providers: extractProviderIDs(from: table)
        )
    }

    private func extractProviderIDs(from table: TOMLTable) -> [String] {
        guard let providers = table["model_providers"]?.tableValue else { return [] }
        return providers.keys.sorted()
    }

    // MARK: - 切换激活 provider

    /// 把 ProviderLayer 的当前激活 provider 注入到 `config.toml`。
    public func applyActiveProvider() async throws {
        var table = try file.loadTable()
        let catalog = try await providerLayer.currentCatalog()

        // 1. 同步 ProviderLayer 里的 providers 到 [model_providers.*]
        for p in catalog.providers {
            ProviderConfigCodec.upsertProvider(p, in: &table)
        }

        // 2. 写 model_provider / requires_openai_auth / model
        if let id = catalog.activeProviderID,
           let active = catalog.providers.first(where: { $0.id == id }) {
            table["model_provider"] = .string(id)
            table["requires_openai_auth"] = .bool(active.authMode == .openaiBearer)
        } else {
            table.removeValue(forKey: "model_provider")
            table.removeValue(forKey: "requires_openai_auth")
        }
        if let model = catalog.defaultModel, !model.isEmpty {
            table["model"] = .string(model)
        } else {
            table.removeValue(forKey: "model")
        }

        try file.saveTable(table)
    }

    /// 撤销本层注入的 key，保留用户原本的 config.toml。
    public func detach() async throws {
        var table = try file.loadTable()
        let catalog = try await providerLayer.currentCatalog()
        for p in catalog.providers {
            ProviderConfigCodec.removeProvider(id: p.id, in: &table)
        }
        table.removeValue(forKey: "model_provider")
        table.removeValue(forKey: "requires_openai_auth")
        table.removeValue(forKey: "model")
        try file.saveTable(table)
    }

    // MARK: - 文件监听

    /// 启动监听 `config.toml` 文件变更。回调会投递到指定 queue。
    public func startWatching(onChange: @escaping @Sendable () -> Void) throws {
        stopWatching()
        let fd = open(file.fileURL.path, O_EVTONLY)
        guard fd >= 0 else {
            throw ConfigLayerError.cannotWatch(file.fileURL.path)
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
            queue: DispatchQueue.global(qos: .utility)
        )
        src.setEventHandler {
            onChange()
        }
        src.setCancelHandler {
            close(fd)
        }
        src.resume()
        self.watchSource = src
    }

    public func stopWatching() {
        watchSource?.cancel()
        watchSource = nil
    }
}

public enum ConfigLayerError: Error, CustomStringConvertible {
    case cannotWatch(String)
    public var description: String {
        switch self { case .cannotWatch(let p): return "cannot watch: \(p)" }
    }
}
