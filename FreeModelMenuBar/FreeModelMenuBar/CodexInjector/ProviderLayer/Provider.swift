import Foundation

/// Codex 的 model_providers 条目。
/// 字段对应 `~/.codex/config.toml` 的 `[model_providers.<id>]` 块：
///   ```toml
///   [model_providers.local-relay]
///   name = "Local relay"
///   base_url = "http://127.0.0.1:11434/v1"
///   wire_api = "chat"             # "chat" | "responses"
///   requires_openai_auth = true
///   experimental_bearer_token = "sk-xxx"
///   ```
public struct Provider: Codable, Equatable, Identifiable, Sendable {
    public enum WireAPI: String, Codable, Sendable, CaseIterable {
        /// OpenAI Chat Completions 协议
        case chat = "chat"
        /// OpenAI Responses 协议（Codex 自身用这个）
        case responses = "responses"
    }

    public enum AuthMode: String, Codable, Sendable, CaseIterable {
        /// 启用 OpenAI 兼容鉴权（让 Codex 发送 `Authorization: Bearer ...`）
        case openaiBearer = "openai_bearer"
        /// 完全不发送鉴权头（适用于本地 mock 中转）
        case none = "none"
    }

    public var id: String
    public var displayName: String
    public var baseURL: URL
    public var wireAPI: WireAPI
    public var authMode: AuthMode
    /// 选 openaiBearer 时，如果设置了 bearerToken，则注入到 `experimental_bearer_token`。
    /// 否则由 AuthLayer 通过环境变量/headers 注入（Codex 桌面端会从 `auth.json` 读 OPENAI_API_KEY）。
    public var bearerToken: String?
    public var notes: String?
    public var createdAt: Date

    public init(
        id: String,
        displayName: String,
        baseURL: URL,
        wireAPI: WireAPI = .responses,
        authMode: AuthMode = .openaiBearer,
        bearerToken: String? = nil,
        notes: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.baseURL = baseURL
        self.wireAPI = wireAPI
        self.authMode = authMode
        self.bearerToken = bearerToken
        self.notes = notes
        self.createdAt = createdAt
    }
}
