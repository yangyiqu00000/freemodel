import Foundation

/// Codex 认证凭据的存储形态，对应 `~/.codex/auth.json` 的内存模型。
/// 来自对 `CC Switch.app/Contents/MacOS/cc-switch` 二进制 strings 的逆向：
///   - API key 模式：`OPENAI_API_KEY` 直接落 `auth.json`
///   - OAuth 模式：包含 `access_token` / `refresh_token` / `email` / `account_id` / `expired`
public struct AuthCredential: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable {
        /// 第三方 / 自定义 provider 用的 API key 形式
        case apiKey = "api_key"
        /// OpenAI 官方 OAuth 登录形式
        case chatgptOAuth = "chatgpt_oauth"
    }

    public var mode: Mode
    public var apiKey: String?
    public var accessToken: String?
    public var refreshToken: String?
    public var idToken: String?
    public var email: String?
    public var accountId: String?
    /// ISO8601 过期时间
    public var expiresAt: Date?
    /// 上次 refresh 的本地时间，用于决定是否需要续期
    public var lastRefresh: Date?

    public init(
        mode: Mode,
        apiKey: String? = nil,
        accessToken: String? = nil,
        refreshToken: String? = nil,
        idToken: String? = nil,
        email: String? = nil,
        accountId: String? = nil,
        expiresAt: Date? = nil,
        lastRefresh: Date? = nil
    ) {
        self.mode = mode
        self.apiKey = apiKey
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.email = email
        self.accountId = accountId
        self.expiresAt = expiresAt
        self.lastRefresh = lastRefresh
    }

    /// Codex 桌面端认的两种字段名都接受（`OPENAI_API_KEY` 是 Codex 实际读取的字段名）。
    public enum CodingKeys: String, CodingKey {
        case mode = "auth_mode"
        case apiKey = "OPENAI_API_KEY"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case email
        case accountId = "account_id"
        case expiresAt = "expired"
        case lastRefresh = "last_refresh"
    }

    public func isExpired(now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }
}
