import Foundation

/// Provider 层对外门面。
/// 责任：
///   - 管理用户自定义 provider 列表
///   - 设置"当前激活 provider"
///   - 把当前激活 provider 序列化成 Codex config.toml 期望的 `model_providers` 块
public actor ProviderLayer {
    public typealias Catalog = ProviderCatalogStore.Catalog

    private let store: ProviderCatalogStore

    public init(store: ProviderCatalogStore = ProviderCatalogStore()) {
        self.store = store
    }

    public func currentCatalog() throws -> Catalog {
        try store.load()
    }

    @discardableResult
    public func upsert(_ provider: Provider) async throws -> Provider {
        var catalog = try store.load()
        if let idx = catalog.providers.firstIndex(where: { $0.id == provider.id }) {
            catalog.providers[idx] = provider
        } else {
            catalog.providers.append(provider)
        }
        try store.save(catalog)
        return provider
    }

    public func deleteProvider(id: String) async throws {
        var catalog = try store.load()
        catalog.providers.removeAll { $0.id == id }
        if catalog.activeProviderID == id {
            catalog.activeProviderID = nil
        }
        try store.save(catalog)
    }

    public func setActive(id: String?) async throws {
        var catalog = try store.load()
        if let id, !catalog.providers.contains(where: { $0.id == id }) {
            throw ProviderError.notFound(id)
        }
        catalog.activeProviderID = id
        try store.save(catalog)
    }

    public func setDefaultModel(_ model: String?) async throws {
        var catalog = try store.load()
        catalog.defaultModel = model
        try store.save(catalog)
    }

    public func activeProvider() throws -> Provider? {
        let catalog = try store.load()
        guard let id = catalog.activeProviderID else { return nil }
        return catalog.providers.first(where: { $0.id == id })
    }
}

public enum ProviderError: Error, CustomStringConvertible {
    case notFound(String)
    public var description: String {
        switch self {
        case .notFound(let id): return "provider not found: \(id)"
        }
    }
}
