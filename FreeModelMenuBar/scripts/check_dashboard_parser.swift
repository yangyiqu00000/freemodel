import Foundation

func assertNearlyEqual(_ actual: Double, _ expected: Double, _ label: String) {
    let delta = abs(actual - expected)
    guard delta < 0.000_001 else {
        fputs("\(label): expected \(expected), got \(actual)\n", stderr)
        exit(1)
    }
}

let usageJSON = """
{
  "totalRequests": 42,
  "totalTokens": 123456,
  "avgLatency": 987,
  "window5h": { "usedCents": 1000, "limitCents": 1000, "resetsAt": 1770000000 },
  "windowWeek": { "usedCents": 4000, "limitCents": 6667, "resetsAt": 1770100000 }
}
""".data(using: .utf8)!

let billingJSON = """
{
  "creditCents": 9044,
  "signupCreditCents": 0,
  "signupExpiresAt": null,
  "subscription": { "planId": "pro", "status": "active" },
  "plans": []
}
""".data(using: .utf8)!

let referralJSON = """
{
  "code": "hidden",
  "count": 1,
  "credits": 90.44,
  "used": 131.06,
  "pendingCents": 0,
  "recent": []
}
""".data(using: .utf8)!

@main
struct DashboardParserCheck {
    static func main() throws {
        let summary = try FreeModelDashboardBalanceParser.parse(
            usageData: usageJSON,
            billingData: billingJSON,
            referralData: referralJSON
        )

        assertNearlyEqual(summary.totalRemaining, 117.11, "totalRemaining")
        assertNearlyEqual(summary.totalUsed, 171.06, "totalUsed")
        assertNearlyEqual(summary.totalGranted, 288.17, "totalGranted")

        print("Dashboard parser checks passed")
    }
}
