import Foundation

/// 用户维护的 provider 列表 + 当前激活 provider 的元数据。
/// 存储在 `~/Library/Application Support/CodexInjector/providers.json`。
public struct ProviderCatalogStore {
    public struct Catalog: Codable, Equatable, Sendable {
        public var providers: [Provider]
        public var activeProviderID: String?
        public var defaultModel: String?

        public init(
            providers: [Provider] = [],
            activeProviderID: String? = nil,
            defaultModel: String? = nil
        ) {
            self.providers = providers
            self.activeProviderID = activeProviderID
            self.defaultModel = defaultModel
        }
    }

    public let fileURL: URL

    public init(fileURL: URL = ProviderCatalogStore.defaultLocation()) {
        self.fileURL = fileURL
    }

    public static func defaultLocation() -> URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("CodexInjector", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("providers.json")
    }

    public func load() throws -> Catalog {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            return Catalog()
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.iso8601.decode(Catalog.self, from: data)
    }

    public func save(_ catalog: Catalog) throws {
        let data = try JSONEncoder.iso8601.encode(catalog)
        try FileSystemSupport.atomicWrite(data: data, to: fileURL)
    }
}
