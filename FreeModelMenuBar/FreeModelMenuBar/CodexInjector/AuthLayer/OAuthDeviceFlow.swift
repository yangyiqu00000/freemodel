import Foundation

/// OpenAI 的 device authorization grant 流程实现。
/// 对应 URL：
///   - usercode:  https://auth.openai.com/api/accounts/deviceauth/usercode
///   - token:     https://auth.openai.com/oauth/token
///   - callback:  https://auth.openai.com/deviceauth/callback
///
/// 用户在浏览器中打开 https://auth.openai.com/codex/device 输入 user_code 即可。
public actor OAuthDeviceFlow {
    public struct DeviceCode: Sendable, Equatable {
        public let deviceCode: String
        public let userCode: String
        public let verificationURL: URL
        public let interval: Int
        public let expiresIn: Int
    }

    public struct TokenResponse: Sendable, Equatable {
        public let accessToken: String
        public let refreshToken: String
        public let idToken: String?
        public let email: String?
        public let accountId: String?
        public let expiresIn: Int
    }

    public enum FlowError: Error, CustomStringConvertible {
        case http(Int, String)
        case pollFailed(String)
        case decode(String)

        public var description: String {
            switch self {
            case .http(let s, let b): return "http \(s): \(b)"
            case .pollFailed(let m): return "poll failed: \(m)"
            case .decode(let m): return "decode failed: \(m)"
            }
        }
    }

    public let clientID: String
    public let baseURL: URL
    public let session: URLSession

    public init(
        clientID: String = "app_EMoamEEZ73f0CkXaXp7hrann",
        baseURL: URL = URL(string: "https://auth.openai.com")!,
        session: URLSession = .shared
    ) {
        self.clientID = clientID
        self.baseURL = baseURL
        self.session = session
    }

    public func requestDeviceCode() async throws -> DeviceCode {
        let url = baseURL.appendingPathComponent("/api/accounts/deviceauth/usercode")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = "client_id=\(clientID)&scope=openid+profile+email"
            .data(using: .utf8)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw FlowError.decode("no http response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw FlowError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FlowError.decode("not an object")
        }
        guard
            let deviceAuthId = obj["device_auth_id"] as? String,
            let userCode = obj["user_code"] as? String,
            let interval = obj["interval"] as? Int,
            let expiresIn = obj["expires_in"] as? Int
        else {
            throw FlowError.decode("missing fields: \(obj.keys.sorted())")
        }
        let verificationURL = URL(string: "https://auth.openai.com/codex/device")!
        return DeviceCode(
            deviceCode: deviceAuthId,
            userCode: userCode,
            verificationURL: verificationURL,
            interval: interval,
            expiresIn: expiresIn
        )
    }

    public func pollForToken(deviceAuthId: String, interval: Int) async throws -> TokenResponse {
        let url = baseURL.appendingPathComponent("/api/accounts/deviceauth/token")
        let deadline = Date().addingTimeInterval(TimeInterval(interval * 60))
        var currentInterval = TimeInterval(interval)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(currentInterval * 1_000_000_000))
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let body = "grant_type=urn:ietf:params:oauth:grant-type:device_code"
                + "&client_id=\(clientID)"
                + "&device_auth_id=\(deviceAuthId)"
            req.httpBody = body.data(using: .utf8)
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                throw FlowError.decode("no http response")
            }
            if (200..<300).contains(http.statusCode) {
                guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw FlowError.decode("not an object")
                }
                guard
                    let access = obj["access_token"] as? String,
                    let refresh = obj["refresh_token"] as? String,
                    let expiresIn = obj["expires_in"] as? Int
                else {
                    throw FlowError.decode("missing token fields")
                }
                let idToken = obj["id_token"] as? String
                let email = (obj["email"] as? String)
                let accountId = (obj["account_id"] as? String) ?? (obj["chatgpt_account_id"] as? String)
                return TokenResponse(
                    accessToken: access,
                    refreshToken: refresh,
                    idToken: idToken,
                    email: email,
                    accountId: accountId,
                    expiresIn: expiresIn
                )
            }
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = obj["error"] as? String {
                if err == "authorization_pending" || err == "slow_down" {
                    if err == "slow_down" { currentInterval += 5 }
                    continue
                }
                throw FlowError.pollFailed(err)
            }
            throw FlowError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        throw FlowError.pollFailed("expired")
    }

    /// 一次性把 device code + token poll 串起来。
    public func runFullFlow(progress: ((DeviceCode) -> Void)? = nil) async throws -> TokenResponse {
        let code = try await requestDeviceCode()
        progress?(code)
        return try await pollForToken(deviceAuthId: code.deviceCode, interval: code.interval)
    }
}
