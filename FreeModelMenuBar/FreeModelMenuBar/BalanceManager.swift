//
//  BalanceManager.swift
//  FreeModelMenuBar
//
//  负责 API 调用、余额查询、定时刷新
//

import Foundation
import SwiftUI

// MARK: - 余额管理器

@MainActor
class BalanceManager: ObservableObject {
    // MARK: - Published Properties

    @Published var balanceInfo: BalanceInfo?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastRefreshDate: Date?
    @Published var refreshInterval: TimeInterval = 300 // 默认5分钟刷新一次

    // MARK: - Private Properties

    private var refreshTimer: Timer?
    private let accountManager: AccountManager

    nonisolated static let dashboardSession = URLSession(configuration: {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 15
        return configuration
    }())

    // MARK: - API Key 管理

    /// 从当前账号读取 API Key（通过 Keychain）
    var apiKey: String? {
        get {
            guard let activeID = accountManager.activeAccountID else { return nil }
            return accountManager.resolveAPIKey(for: activeID)
        }
        set {
            guard let activeAccount = accountManager.activeAccount else { return }
            accountManager.updateAPIKey(newValue, for: activeAccount.id)
        }
    }

    /// 是否已配置（已登录控制台，或已设置 API Key）。避免在启动和菜单渲染时直接读取 Keychain。
    var isConfigured: Bool {
        guard let account = accountManager.activeAccount else { return false }
        switch account.queryMode {
        case .dashboard:
            return account.hasDashboardSession
        case .apiKey:
            return account.hasAPIKey
        }
    }

    var hasDashboardCookies: Bool {
        guard let account = accountManager.activeAccount else { return false }
        return account.queryMode == .dashboard && account.hasDashboardSession
    }

    // MARK: - 初始化

    init(accountManager: AccountManager) {
        self.accountManager = accountManager
        self.balanceInfo = accountManager.activeAccount?.lastBalance
        self.lastRefreshDate = accountManager.activeAccount?.lastRefreshDate
        self.refreshInterval = accountManager.activeAccount?.refreshInterval ?? 300

        // 只在已配置时自动刷新。
        if isConfigured {
            Task {
                await fetchBalance()
            }
        }
        startAutoRefresh()
    }

    deinit {
        refreshTimer?.invalidate()
    }

    // MARK: - 定时刷新

    func startAutoRefresh() {
        stopAutoRefresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fetchBalance()
            }
        }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func updateRefreshInterval(_ interval: TimeInterval) {
        refreshInterval = interval
        if let activeAccount = accountManager.activeAccount {
            accountManager.updateRefreshInterval(interval, for: activeAccount.id)
        }
        if refreshTimer != nil {
            startAutoRefresh()
        }
    }

    // MARK: - API 调用

    /// 查询余额 - 支持控制台网页模式与 API Key 模式
    func fetchBalance() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let account = accountManager.activeAccount else {
            self.balanceInfo = nil
            self.lastRefreshDate = nil
            self.errorMessage = "请先在设置中添加账号"
            return
        }

        switch account.queryMode {
        case .dashboard:
            guard account.hasDashboardSession else {
                self.balanceInfo = account.lastBalance
                self.lastRefreshDate = account.lastRefreshDate
                self.errorMessage = FreeModelError.dashboardLoginRequired.errorDescription
                return
            }

            do {
                let result = try await queryDashboardBalance(account: account)
                accountManager.updateBalance(result, for: account.id)
                self.balanceInfo = result
                self.lastRefreshDate = result.lastUpdated
            } catch FreeModelError.dashboardLoginRequired {
                self.balanceInfo = nil
                self.errorMessage = FreeModelError.dashboardLoginRequired.errorDescription
            } catch {
                self.errorMessage = (error as? FreeModelError)?.errorDescription ?? error.localizedDescription
            }

        case .apiKey:
            guard let apiKey = apiKey, !apiKey.isEmpty else {
                self.balanceInfo = account.lastBalance
                self.lastRefreshDate = account.lastRefreshDate
                self.errorMessage = "请先在设置中配置 API Key"
                return
            }

            let endpoints = balanceEndpoints(for: account)

            var lastError: FreeModelError?
            var fetchSuccess = false

            for endpoint in endpoints {
                do {
                    let result = try await queryEndpoint(endpoint, apiKey: apiKey, apiBaseURL: account.apiBaseURL)
                    accountManager.updateBalance(result, for: account.id)
                    self.balanceInfo = result
                    self.lastRefreshDate = result.lastUpdated
                    fetchSuccess = true
                    break
                } catch {
                    lastError = (error as? FreeModelError) ?? .networkError(error)
                    continue
                }
            }

            if fetchSuccess {
                return
            }

            // 所有端点都失败，尝试使用 models 端点来验证 API Key 是否有效
            do {
                _ = try await queryModelsEndpoint(apiKey: apiKey, apiBaseURL: account.apiBaseURL)
                self.errorMessage = "API Key 有效，但 FreeModel 未开放 API Key 余额查询接口。请使用控制台网页登录态获取余额。"
            } catch {
                self.errorMessage = lastError?.errorDescription ?? "无法连接到 FreeModel API"
            }
        }
    }

    /// API Key 只用于验证 OpenAI-compatible API 是否可用，不再用于余额查询。
    func validateAPIKey(_ key: String) async -> Result<Void, FreeModelError> {
        do {
            let baseURL = accountManager.activeAccount?.apiBaseURL ?? "https://api.freemodel.dev"
            _ = try await queryModelsEndpoint(apiKey: key, apiBaseURL: baseURL)
            return .success(())
        } catch let error as FreeModelError {
            return .failure(error)
        } catch {
            return .failure(.networkError(error))
        }
    }

    func syncFromActiveAccount() {
        balanceInfo = accountManager.activeAccount?.lastBalance
        lastRefreshDate = accountManager.activeAccount?.lastRefreshDate
        errorMessage = nil
        if let account = accountManager.activeAccount {
            refreshInterval = account.refreshInterval
            startAutoRefresh()
        }
    }

    private func queryDashboardBalance(account: ProviderAccount) async throws -> BalanceInfo {
        async let usage = queryRequiredDashboardEndpoint("/api/usage", account: account)
        async let billing = queryRequiredDashboardEndpoint("/api/billing", account: account)
        async let referral = queryOptionalDashboardEndpoint("/api/referral", account: account)

        return try await FreeModelDashboardBalanceParser.parse(
            usageData: usage,
            billingData: billing,
            referralData: referral
        )
    }

    private func queryRequiredDashboardEndpoint(_ endpoint: String, account: ProviderAccount) async throws -> Data {
        guard let data = try await queryDashboardEndpoint(endpoint, account: account, required: true) else {
            throw FreeModelError.invalidResponse
        }
        return data
    }

    private func queryOptionalDashboardEndpoint(_ endpoint: String, account: ProviderAccount) async throws -> Data? {
        try await queryDashboardEndpoint(endpoint, account: account, required: false)
    }

    private func queryDashboardEndpoint(_ endpoint: String, account: ProviderAccount, required: Bool) async throws -> Data? {
        guard !account.cookieHeader.isEmpty else {
            throw FreeModelError.dashboardLoginRequired
        }
        guard let url = URL(string: "\(account.dashboardURL)\(endpoint)") else {
            throw FreeModelError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(account.dashboardURL, forHTTPHeaderField: "Origin")
        request.setValue("\(account.dashboardURL)/dashboard/usage", forHTTPHeaderField: "Referer")
        request.setValue(account.cookieHeader, forHTTPHeaderField: "Cookie")
        request.timeoutInterval = 15

        let (data, response) = try await Self.dashboardSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FreeModelError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return data
        case 401, 403:
            if required {
                throw FreeModelError.dashboardLoginRequired
            }
            return nil
        case 404:
            if required {
                throw FreeModelError.serverError(404, "\(endpoint) 不存在")
            }
            return nil
        default:
            if required {
                let message = String(data: data, encoding: .utf8) ?? "未知错误"
                throw FreeModelError.serverError(httpResponse.statusCode, message)
            }
            return nil
        }
    }

    /// 查询单个端点
    private func queryEndpoint(_ endpoint: String, apiKey: String, apiBaseURL: String) async throws -> BalanceInfo {
        guard let url = makeEndpointURL(apiBaseURL: apiBaseURL, endpoint: endpoint) else {
            throw FreeModelError.invalidResponse
        }

        let request = Self.makeAuthorizedRequest(url: url, apiKey: apiKey, acceptJSON: true)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FreeModelError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401, 403:
            throw FreeModelError.invalidAPIKey
        case 402:
            throw FreeModelError.serverError(402, "账户需要验证或充值")
        case 429:
            throw FreeModelError.serverError(429, "请求过于频繁，请稍后再试")
        default:
            let message = String(data: data, encoding: .utf8) ?? "未知错误"
            throw FreeModelError.serverError(httpResponse.statusCode, message)
        }

        // 尝试解析余额数据
        return try parseBalanceResponse(data, endpoint: endpoint)
    }

    /// 查询 models 端点（用于验证 API Key）
    private func queryModelsEndpoint(apiKey: String, apiBaseURL: String) async throws -> Bool {
        guard let url = makeEndpointURL(apiBaseURL: apiBaseURL, endpoint: "/v1/models") else {
            throw FreeModelError.invalidResponse
        }

        let request = Self.makeAuthorizedRequest(url: url, apiKey: apiKey, acceptJSON: false)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FreeModelError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return true
        case 401, 403:
            throw FreeModelError.invalidAPIKey
        default:
            throw FreeModelError.serverError(httpResponse.statusCode, "验证失败")
        }
    }


    /// 构造带 Bearer Token 的 GET 请求。3 个 endpoint 查询共用，统一 timeout 与 header。
    private static func makeAuthorizedRequest(url: URL, apiKey: String, acceptJSON: Bool) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if acceptJSON {
            request.setValue("application/json", forHTTPHeaderField: "Accept")
        }
        request.timeoutInterval = 15
        return request
    }

    private func balanceEndpoints(for account: ProviderAccount) -> [String] {
        let apiURL = account.apiBaseURL.lowercased()
        let isDeepSeek = account.providerID == "deepseek" || apiURL.contains("deepseek.com")
        if isDeepSeek {
            return [
                "/user/balance",
                "/v1/user/balance",
                "/balance",
                "/v1/balance"
            ]
        }

        // OpenRouter 专用：它的余额是 credit 体系（不是 OpenAI 的 hard_limit_usd），
        // 唯一有效端点是 /api/v1/auth/key，返回 { data: { limit, usage, limit_remaining } }。
        // OpenAI 通用端点（/v1/dashboard/billing/*）在 OpenRouter 返回 HTML 404，不能用。
        if account.providerID == "openrouter" || apiURL.contains("openrouter.ai") {
            return [
                "/api/v1/auth/key",
                "/api/v1/key"
            ]
        }

        return [
            "/v1/dashboard/billing/subscription",
            "/v1/dashboard/billing/credit_grants",
            "/user/balance",
            "/v1/user/balance",
            "/balance",
            "/v1/balance",
            "/dashboard/billing/subscription",
            "/dashboard/billing/credit_grants"
        ]
    }

    private func makeEndpointURL(apiBaseURL: String, endpoint: String) -> URL? {
        var base = apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") {
            base.removeLast()
        }

        let path = endpoint.hasPrefix("/") ? endpoint : "/\(endpoint)"
        let lowerBase = base.lowercased()

        if lowerBase.contains("api.deepseek.com"), path == "/user/balance" {
            base = base.replacingOccurrences(of: #"/v1$"#, with: "", options: .regularExpression)
        }

        if base.hasSuffix("/v1"), path.hasPrefix("/v1/") {
            return URL(string: base + String(path.dropFirst(3)))
        }

        return URL(string: base + path)
    }

    private func parseDouble(_ value: Any?) -> Double {
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

    /// 解析余额响应数据
    private func parseBalanceResponse(_ data: Data, endpoint: String) throws -> BalanceInfo {
        var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        // OpenRouter /api/v1/auth/key 格式：{ data: { label, usage, limit, limit_remaining, ... } }
        // data 是字典（不是数组），需要 unwrap 后再走通用解析。
        if let dataObj = json["data"] as? [String: Any] {
            json = dataObj
        }

        // OpenRouter credit 格式（/api/v1/auth/key unwrap 后）：usage + limit + limit_remaining
        // limit 可能为 null（无月限额 = 用多少扣多少）。有 limit 时：已用=usage, 总额=limit, 剩余=limit_remaining。
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
        if let hardLimitUSD = json["hard_limit_usd"] as? Double,
           let accessUntil = json["access_until"] as? Double {
            let totalUsed = json["total_usage"] as? Double ?? 0
            return BalanceInfo(
                totalGranted: hardLimitUSD,
                totalUsed: totalUsed / 100.0, // OpenAI 以美分为单位
                totalRemaining: hardLimitUSD - (totalUsed / 100.0),
                expiresAt: Date(timeIntervalSince1970: accessUntil),
                lastUpdated: Date()
            )
        }

        // OpenAI 风格: /v1/dashboard/billing/credit_grants
        if let grants = json["total_granted"] as? Double,
           let used = json["total_used"] as? Double {
            return BalanceInfo(
                totalGranted: grants,
                totalUsed: used,
                totalRemaining: grants - used,
                expiresAt: nil,
                lastUpdated: Date()
            )
        }

        // 通用格式: balance / remaining / total
        if let balance = json["balance"] as? Double {
            let total = json["total"] as? Double ?? json["total_quota"] as? Double ?? 300.0
            let used = json["used"] as? Double ?? json["total_used"] as? Double ?? (total - balance)
            return BalanceInfo(
                totalGranted: total,
                totalUsed: used,
                totalRemaining: balance,
                expiresAt: nil,
                lastUpdated: Date()
            )
        }

        // 简单格式: remaining
        if let remaining = json["remaining"] as? Double {
            let total = json["total"] as? Double ?? json["total_quota"] as? Double ?? 300.0
            return BalanceInfo(
                totalGranted: total,
                totalUsed: total - remaining,
                totalRemaining: remaining,
                expiresAt: nil,
                lastUpdated: Date()
            )
        }

        // data 数组格式
        if let dataArray = json["data"] as? [[String: Any]], let first = dataArray.first {
            return try parseBalanceResponse(
                try JSONSerialization.data(withJSONObject: first),
                endpoint: endpoint
            )
        }

        throw FreeModelError.decodingError
    }
}
