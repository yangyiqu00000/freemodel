import Foundation

/// 读写 `~/.codex/auth.json`。
/// 该文件是 Codex 桌面端（和 CLI）共同读取的认证源。
/// 我们直接以 Codex 期望的 JSON 结构写入。
public struct AuthJSONStore {
    // ISO8601DateFormatter 自 iOS 10 起线程安全，可作为 static let 复用避免每次 decode/encode 都新建。
    fileprivate static let iso8601Formatter = ISO8601DateFormatter()

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultLocation(codexHome: URL? = nil) -> AuthJSONStore {
        let home = codexHome ?? CodexHomeLocator.resolve()
        return AuthJSONStore(fileURL: home.appendingPathComponent("auth.json"))
    }

    public func load() throws -> AuthCredential? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        // Codex 实际写入的 JSON 顶层通常只是 `{"OPENAI_API_KEY": "..."}`
        // 或者是 `{"access_token": "...", "refresh_token": "...", ...}`。
        // 我们用最宽松的方式解析——任何字段被填了都接受。
        return try AuthJSONLooser.decode(data: data)
    }

    /// 写入 auth.json。原子写入：先写临时文件再 rename，避免 Codex 读到半截文件。
    public func save(_ credential: AuthCredential) throws {
        let data = try AuthJSONLooser.encode(credential: credential)
        try FileSystemSupport.atomicWrite(data: data, to: fileURL)
        // 600 权限：仅当前用户可读写。Codex 桌面端也需要这个权限。
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    public func clear() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: fileURL.path) {
            try fm.removeItem(at: fileURL)
        }
    }
}

/// 在 Codex 自己的 JSON 格式和我们的 `AuthCredential` 之间转译。
/// 不引入强 schema，因为 Codex 自己也在演进这块字段集。
enum AuthJSONLooser {
    static func decode(data: Data) throws -> AuthCredential? {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let apiKey = obj["OPENAI_API_KEY"] as? String
        let access = obj["access_token"] as? String
        let refresh = obj["refresh_token"] as? String
        let idToken = obj["id_token"] as? String
        let email = obj["email"] as? String
        let accountId = obj["account_id"] as? String
        let lastRefreshStr = obj["last_refresh"] as? String
        let lastRefresh = lastRefreshStr.flatMap { AuthJSONStore.iso8601Formatter.date(from: $0) }

        let mode: AuthCredential.Mode
        if apiKey != nil && (access == nil) {
            mode = .apiKey
        } else if access != nil {
            mode = .chatgptOAuth
        } else {
            return nil
        }
        return AuthCredential(
            mode: mode,
            apiKey: apiKey,
            accessToken: access,
            refreshToken: refresh,
            idToken: idToken,
            email: email,
            accountId: accountId,
            expiresAt: nil,
            lastRefresh: lastRefresh
        )
    }

    static func encode(credential: AuthCredential) throws -> Data {
        var obj: [String: Any] = [:]
        switch credential.mode {
        case .apiKey:
            if let v = credential.apiKey { obj["OPENAI_API_KEY"] = v }
        case .chatgptOAuth:
            if let v = credential.accessToken { obj["access_token"] = v }
            if let v = credential.refreshToken { obj["refresh_token"] = v }
            if let v = credential.idToken { obj["id_token"] = v }
            if let v = credential.email { obj["email"] = v }
            if let v = credential.accountId { obj["account_id"] = v }
        }
        if let d = credential.lastRefresh {
            obj["last_refresh"] = AuthJSONStore.iso8601Formatter.string(from: d)
        }
        return try JSONSerialization.data(
            withJSONObject: obj,
            options: [.prettyPrinted, .sortedKeys]
        )
    }
}
