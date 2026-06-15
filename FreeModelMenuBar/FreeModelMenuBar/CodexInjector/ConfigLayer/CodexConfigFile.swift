import Foundation

/// 读写 `~/.codex/config.toml`。
/// 关键设计：
///   - 解析后用顶层 TOMLTable 操作，序列化回 TOML 文本
///   - 保留所有非本层管理的 key（mcp_servers、approval_policy、sandbox_mode 等）
///   - 注入本层管理的 key：
///       * `model_provider`：当前激活 provider id
///       * `[model_providers.<id>]`：单个 provider 的 TOML 表
///       * `model`：默认 model（可选）
///       * `requires_openai_auth`：仅在使用自定义 provider 时需要
public struct CodexConfigFile {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultLocation(codexHome: URL? = nil) -> CodexConfigFile {
        let home = codexHome ?? CodexHomeLocator.resolve()
        return CodexConfigFile(fileURL: home.appendingPathComponent("config.toml"))
    }

    public enum LoadError: Error, CustomStringConvertible {
        case parseFailed(String)
        public var description: String {
            switch self { case .parseFailed(let m): return "config.toml parse failed: \(m)" }
        }
    }

    public func loadTable() throws -> TOMLTable {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return TOMLTable() }
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        do {
            return try TOMLParser().parse(text)
        } catch {
            throw LoadError.parseFailed(String(describing: error))
        }
    }

    public func saveTable(_ table: TOMLTable) throws {
        let text = TOMLSerializer().serialize(table: table)
        try FileSystemSupport.atomicWrite(
            data: Data(text.utf8),
            to: fileURL
        )
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}
