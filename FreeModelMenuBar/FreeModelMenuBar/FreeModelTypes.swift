//
//  FreeModelTypes.swift
//  FreeModelMenuBar
//
//  Shared balance and error types.
//

import Foundation

struct StoredCookie: Codable, Equatable, Identifiable {
    var id: String { "\(domain)|\(path)|\(name)" }

    let name: String
    let value: String
    let domain: String
    let path: String
    let expiresAt: Date?
    let isSecure: Bool
    let isHTTPOnly: Bool

    init(
        name: String,
        value: String,
        domain: String,
        path: String,
        expiresAt: Date?,
        isSecure: Bool,
        isHTTPOnly: Bool
    ) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.expiresAt = expiresAt
        self.isSecure = isSecure
        self.isHTTPOnly = isHTTPOnly
    }

    init(cookie: HTTPCookie) {
        self.name = cookie.name
        self.value = cookie.value
        self.domain = cookie.domain
        self.path = cookie.path
        self.expiresAt = cookie.expiresDate
        self.isSecure = cookie.isSecure
        self.isHTTPOnly = cookie.isHTTPOnly
    }

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }

    var headerPair: String {
        let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
        return "\(name)=\(encodedValue)"
    }

    func makeHTTPCookie() -> HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path,
            .version: "0"
        ]

        if let expiresAt {
            properties[.expires] = expiresAt
        }
        if isSecure {
            properties[.secure] = "TRUE"
        }
        if isHTTPOnly {
            properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE"
        }

        return HTTPCookie(properties: properties)
    }
}
/// 余额信息模型
struct BalanceInfo: Codable, Equatable {
    let totalGranted: Double
    let totalUsed: Double
    let totalRemaining: Double
    let expiresAt: Date?
    let lastUpdated: Date
    let currency: String?

    init(
        totalGranted: Double,
        totalUsed: Double,
        totalRemaining: Double,
        expiresAt: Date?,
        lastUpdated: Date,
        currency: String? = nil
    ) {
        self.totalGranted = totalGranted
        self.totalUsed = totalUsed
        self.totalRemaining = totalRemaining
        self.expiresAt = expiresAt
        self.lastUpdated = lastUpdated
        self.currency = currency
    }

    var currencySymbol: String {
        (currency == "CNY" || currency == "人民币") ? "￥" : "$"
    }

    /// 统一 3 个 *Formatted 字段，避免各处重复 String(format:)
    private func formatAmount(_ value: Double) -> String {
        String(format: "%@%.2f", currencySymbol, value)
    }

    var remainingFormatted: String { formatAmount(totalRemaining) }
    var usedFormatted: String { formatAmount(totalUsed) }
    var totalFormatted: String { formatAmount(totalGranted) }

    var usagePercentage: Double {
        guard totalGranted > 0 else { return 0 }
        return (totalUsed / totalGranted) * 100
    }

    var isLow: Bool {
        totalRemaining < 5.0
    }

    var isExhausted: Bool {
        totalRemaining <= 0
    }
}

/// 查询余额模式
enum QueryMode: String, Codable, CaseIterable {
    case dashboard = "网页控制台"
    case apiKey = "API Key"
}

/// API 错误类型
enum FreeModelError: LocalizedError {
    case invalidAPIKey
    case dashboardLoginRequired
    case networkError(Error)
    case invalidResponse
    case serverError(Int, String)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "API Key 无效，请在设置中检查"
        case .dashboardLoginRequired:
            return "请先登录当前账号的 FreeModel 控制台，然后再刷新余额"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .invalidResponse:
            return "服务器返回了无效的响应"
        case .serverError(let code, let message):
            return "服务器错误 (\(code)): \(message)"
        case .decodingError:
            return "数据解析失败"

        }
    }
}

// MARK: - 余额响应解析器

/// 将不同服务商的余额 API JSON 响应统一解析为 BalanceInfo。
/// 支持格式：OpenRouter / DeepSeek / OpenAI Subscription / OpenAI Credit Grants / 通用 / 简单。
/// 纯函数，无依赖，可直接用于单元测试。
struct BalanceResponseParser {
    private init() {}

    static func parseDouble(_ value: Any?) -> Double {
        if let doubleValue = value as? Double {
            return doubleValue
        }
        if let stringValue = value as? String, let doubleValue = Double(stringValue) {
            return doubleValue
        }
        if let intValue = value as? Int {
            return Double(intValue)
        }
        return 0.0
    }

    /// 从 JSON 字典中提取 Double，支持 String/Int/Number 类型。
    /// 仅当 key 存在时返回有效值；不存在或 nil 时返回 nil（区别于 parseDouble 的 0.0 兜底）。
    static func optDouble(_ json: [String: Any], _ key: String) -> Double? {
        guard let raw = json[key] else { return nil }
        // nil inside JSON can be NSNull
        if raw is NSNull { return nil }
        let val = parseDouble(raw)
        // parseDouble returns 0.0 for truly unparseable, but we can't distinguish
        // "key exists with value 0" from "key exists but unparseable". Accept 0.0 as valid.
        return val
    }

    /// 解析余额响应数据
    /// - Parameters:
    ///   - data: API 返回的 JSON 数据
    ///   - endpoint: 请求的端点路径（仅用于日志/调试）
    /// - Returns: 统一后的 BalanceInfo
    static func parseBalanceResponse(_ data: Data, endpoint: String) throws -> BalanceInfo {
        var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        // OpenRouter /api/v1/auth/key 格式：{ data: { label, usage, limit, limit_remaining, ... } }
        if let dataObj = json["data"] as? [String: Any] {
            json = dataObj
        }

        // OpenRouter credit 格式
        if json["limit_remaining"] != nil {
            let limit = parseDouble(json["limit"])
            let usage = parseDouble(json["usage"])
            let remaining = parseDouble(json["limit_remaining"])
            return BalanceInfo(
                totalGranted: limit,
                totalUsed: usage,
                totalRemaining: remaining,
                expiresAt: nil,
                lastUpdated: Date(),
                currency: "USD"
            )
        }

        // DeepSeek 格式: balance_infos
        if let balanceInfos = json["balance_infos"] as? [[String: Any]],
           let firstInfo = balanceInfos.first {
            let currency = firstInfo["currency"] as? String ?? "CNY"
            let totalRemaining = parseDouble(firstInfo["total_balance"])
            let granted = parseDouble(firstInfo["granted_balance"])
            let toppedUp = parseDouble(firstInfo["topped_up_balance"])
            let totalGranted = granted + toppedUp
            let totalUsed = max(0, totalGranted - totalRemaining)

            return BalanceInfo(
                totalGranted: totalGranted > 0 ? totalGranted : totalRemaining,
                totalUsed: totalUsed,
                totalRemaining: totalRemaining,
                expiresAt: nil,
                lastUpdated: Date(),
                currency: currency
            )
        }

        // OpenAI 风格: /v1/dashboard/billing/subscription
        if let hardLimitUSD = optDouble(json, "hard_limit_usd"),
           let accessUntil = optDouble(json, "access_until") {
            let totalUsed = optDouble(json, "total_usage") ?? 0
            return BalanceInfo(
                totalGranted: hardLimitUSD,
                totalUsed: totalUsed / 100.0,
                totalRemaining: hardLimitUSD - (totalUsed / 100.0),
                expiresAt: Date(timeIntervalSince1970: accessUntil),
                lastUpdated: Date()
            )
        }

        // OpenAI 风格: /v1/dashboard/billing/credit_grants
        if let grants = optDouble(json, "total_granted"),
           let used = optDouble(json, "total_used") {
            return BalanceInfo(
                totalGranted: grants,
                totalUsed: used,
                totalRemaining: grants - used,
                expiresAt: nil,
                lastUpdated: Date()
            )
        }

        // 通用格式: balance / remaining / total
        if let balance = optDouble(json, "balance") {
            let total = optDouble(json, "total") ?? optDouble(json, "total_quota") ?? 300.0
            let used = optDouble(json, "used") ?? optDouble(json, "total_used") ?? (total - balance)
            return BalanceInfo(
                totalGranted: total,
                totalUsed: used,
                totalRemaining: balance,
                expiresAt: nil,
                lastUpdated: Date()
            )
        }

        // 简单格式: remaining
        if let remaining = optDouble(json, "remaining") {
            let total = optDouble(json, "total") ?? optDouble(json, "total_quota") ?? 300.0
            return BalanceInfo(
                totalGranted: total,
                totalUsed: total - remaining,
                totalRemaining: remaining,
                expiresAt: nil,
                lastUpdated: Date()
            )
        }

        throw FreeModelError.decodingError
    }
}

