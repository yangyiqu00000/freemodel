//
//  FreeModelDashboardParser.swift
//  FreeModelMenuBar
//
//  解析 FreeModel 控制台用量接口。
//

import Foundation

struct FreeModelDashboardBalanceParser {
    private struct UsageResponse: Decodable {
        let window5h: UsageWindow?
        let windowWeek: UsageWindow?
    }

    private struct UsageWindow: Decodable {
        let usedCents: Double?
        let limitCents: Double?
        let resetsAt: Double?
    }

    private struct BillingResponse: Decodable {
        let creditCents: Double?
        let signupCreditCents: Double?
    }

    private struct ReferralResponse: Decodable {
        let count: Int?
        let credits: Double?
        let used: Double?
    }

    static func parse(usageData: Data, billingData: Data, referralData: Data?) throws -> BalanceInfo {
        let decoder = JSONDecoder()
        let usage = try decoder.decode(UsageResponse.self, from: usageData)
        let billing = try decoder.decode(BillingResponse.self, from: billingData)
        let referral = try referralData.map { try decoder.decode(ReferralResponse.self, from: $0) }

        let weekUsed = centsToDollars(usage.windowWeek?.usedCents)
        let weekLimit = centsToDollars(usage.windowWeek?.limitCents)
        let planRemaining = max(0, weekLimit - weekUsed)

        let signupRemaining = centsToDollars(billing.signupCreditCents)
        let extraRemaining: Double
        let extraUsed: Double

        if let referral {
            extraRemaining = max(0, (referral.credits ?? 0) + signupRemaining)
            extraUsed = max(0, referral.used ?? 0)
        } else {
            extraRemaining = max(0, centsToDollars(billing.creditCents))
            extraUsed = 0
        }

        let totalRemaining = planRemaining + extraRemaining
        let totalUsed = weekUsed + extraUsed
        let totalGranted = totalRemaining + totalUsed
        let resetTimestamp = usage.windowWeek?.resetsAt ?? usage.window5h?.resetsAt

        return BalanceInfo(
            totalGranted: totalGranted,
            totalUsed: totalUsed,
            totalRemaining: totalRemaining,
            expiresAt: resetTimestamp.map { Date(timeIntervalSince1970: $0) },
            lastUpdated: Date()
        )
    }

    private static func centsToDollars(_ cents: Double?) -> Double {
        (cents ?? 0) / 100.0
    }
}
