//
//  FreeModelTypes.swift
//  FreeModelMenuBar
//
//  Shared balance and error types.
//

import Foundation

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

    var remainingFormatted: String {
        String(format: "%@%.2f", currencySymbol, totalRemaining)
    }

    var usedFormatted: String {
        String(format: "%@%.2f", currencySymbol, totalUsed)
    }

    var totalFormatted: String {
        String(format: "%@%.2f", currencySymbol, totalGranted)
    }

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
