import Foundation

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
    guard actual != expected else { return }
    print("balance-parser-test-fail: \(label): expected \(expected), got \(actual)")
    exit(1)
}

func assertNearlyEqual(_ actual: Double, _ expected: Double, _ label: String) {
    let delta = abs(actual - expected)
    guard delta < 0.000_001 else {
        print("balance-parser-test-fail: \(label): expected \(expected), got \(actual)")
        exit(1)
    }
}

func assertThrows<T>(_ expr: @autoclosure () throws -> T, _ label: String) {
    do {
        _ = try expr()
        print("balance-parser-test-fail: \(label): expected error but got success")
        exit(1)
    } catch {
        // expected
    }
}

// ── Fixtures ──

// 1. OpenRouter credit 格式
let openRouterJSON = """
{"data":{"label":"My Key","usage":12.34,"limit":100.00,"limit_remaining":87.66,"is_free_tier":false}}
""".data(using: .utf8)!

// 2. DeepSeek 格式
let deepSeekJSON = """
{"balance_infos":[{"currency":"CNY","total_balance":88.50,"granted_balance":50.00,"topped_up_balance":50.00}]}
""".data(using: .utf8)!

// 3. OpenAI 订阅格式
let openAISubJSON = """
{"hard_limit_usd":120.00,"access_until":1893456000,"total_usage":4567}
""".data(using: .utf8)!

// 4. OpenAI Credit Grants 格式
let openAICreditJSON = """
{"total_granted":50.00,"total_used":12.50,"total_available":37.50}
""".data(using: .utf8)!

// 5. 通用格式 (balance)
let genericJSON = """
{"balance":25.00,"total":100.00,"used":75.00}
""".data(using: .utf8)!

// 6. 简单格式 (remaining)
let simpleJSON = """
{"remaining":30.00,"total":200.00}
""".data(using: .utf8)!

// 7. 通用格式带 total_quota
let genericQuotaJSON = """
{"balance":15.00,"total_quota":50.00}
""".data(using: .utf8)!

// 8. 错误数据（无法解析）
let invalidJSON = """
{"foo":"bar"}
""".data(using: .utf8)!

// 9. OpenRouter limit = null（无月限额）
let openRouterNoLimitJSON = """
{"data":{"label":"Pay-as-you-go","usage":5.00,"limit":null,"limit_remaining":null}}
""".data(using: .utf8)!

// 10. 字符串数字测试 parseDouble 兼容性
let stringNumberJSON = """
{"remaining":"42.50","total":"100.00"}
""".data(using: .utf8)!

// 11. Int 数字测试
let intNumberJSON = """
{"remaining":50,"total":200}
""".data(using: .utf8)!

// ── Tests ──

func testOpenRouter() throws {
    let r = try BalanceResponseParser.parseBalanceResponse(openRouterJSON, endpoint: "/api/v1/auth/key")
    assertNearlyEqual(r.totalGranted, 100.00, "OpenRouter totalGranted")
    assertNearlyEqual(r.totalUsed, 12.34, "OpenRouter totalUsed")
    assertNearlyEqual(r.totalRemaining, 87.66, "OpenRouter totalRemaining")
    assertEqual(r.currency, "USD", "OpenRouter currency")
    assertEqual(r.currencySymbol, "$", "OpenRouter currencySymbol")
    print("✅ OpenRouter: pass")
}

func testDeepSeek() throws {
    let r = try BalanceResponseParser.parseBalanceResponse(deepSeekJSON, endpoint: "/user/balance")
    assertNearlyEqual(r.totalGranted, 100.00, "DeepSeek totalGranted (granted 50 + toppedUp 50)")
    assertNearlyEqual(r.totalRemaining, 88.50, "DeepSeek totalRemaining")
    assertNearlyEqual(r.totalUsed, 11.50, "DeepSeek totalUsed (100 - 88.50)")
    assertEqual(r.currency, "CNY", "DeepSeek currency")
    assertEqual(r.currencySymbol, "￥", "DeepSeek currencySymbol")
    print("✅ DeepSeek: pass")
}

func testOpenAISubscription() throws {
    let r = try BalanceResponseParser.parseBalanceResponse(openAISubJSON, endpoint: "/v1/dashboard/billing/subscription")
    assertNearlyEqual(r.totalGranted, 120.00, "OpenAI Sub totalGranted")
    assertNearlyEqual(r.totalUsed, 45.67, "OpenAI Sub totalUsed (4567 cents / 100)")
    assertNearlyEqual(r.totalRemaining, 74.33, "OpenAI Sub totalRemaining (120 - 45.67)")
    assertEqual(r.expiresAt, Date(timeIntervalSince1970: 1_893_456_000), "OpenAI Sub expiresAt")
    print("✅ OpenAI Subscription: pass")
}

func testOpenAICreditGrants() throws {
    let r = try BalanceResponseParser.parseBalanceResponse(openAICreditJSON, endpoint: "/v1/dashboard/billing/credit_grants")
    assertNearlyEqual(r.totalGranted, 50.00, "OpenAI Credit totalGranted")
    assertNearlyEqual(r.totalUsed, 12.50, "OpenAI Credit totalUsed")
    assertNearlyEqual(r.totalRemaining, 37.50, "OpenAI Credit totalRemaining")
    print("✅ OpenAI Credit Grants: pass")
}

func testGenericBalance() throws {
    let r = try BalanceResponseParser.parseBalanceResponse(genericJSON, endpoint: "/balance")
    assertNearlyEqual(r.totalGranted, 100.00, "Generic totalGranted")
    assertNearlyEqual(r.totalUsed, 75.00, "Generic totalUsed")
    assertNearlyEqual(r.totalRemaining, 25.00, "Generic totalRemaining")
    print("✅ Generic (balance/total/used): pass")
}

func testSimpleRemaining() throws {
    let r = try BalanceResponseParser.parseBalanceResponse(simpleJSON, endpoint: "/remaining")
    assertNearlyEqual(r.totalGranted, 200.00, "Simple totalGranted")
    assertNearlyEqual(r.totalUsed, 170.00, "Simple totalUsed (200-30)")
    assertNearlyEqual(r.totalRemaining, 30.00, "Simple totalRemaining")
    print("✅ Simple (remaining/total): pass")
}

func testGenericQuota() throws {
    let r = try BalanceResponseParser.parseBalanceResponse(genericQuotaJSON, endpoint: "/balance")
    assertNearlyEqual(r.totalGranted, 50.00, "Quota totalGranted (total_quota)")
    assertNearlyEqual(r.totalUsed, 35.00, "Quota totalUsed (50-15)")
    assertNearlyEqual(r.totalRemaining, 15.00, "Quota totalRemaining")
    print("✅ Generic with total_quota: pass")
}

func testInvalidJSON() throws {
    assertThrows(try BalanceResponseParser.parseBalanceResponse(invalidJSON, endpoint: "/invalid"), "Invalid JSON should throw")
    print("✅ Invalid JSON throws: pass")
}

func testOpenRouterNoLimit() throws {
    let r = try BalanceResponseParser.parseBalanceResponse(openRouterNoLimitJSON, endpoint: "/api/v1/auth/key")
    assertNearlyEqual(r.totalGranted, 0, "OpenRouter no-limit totalGranted (limit=null)")
    assertNearlyEqual(r.totalUsed, 5.00, "OpenRouter no-limit totalUsed")
    assertNearlyEqual(r.totalRemaining, 0, "OpenRouter no-limit totalRemaining (limit_remaining=null)")
    print("✅ OpenRouter no-limit (null): pass")
}

func testStringNumbers() throws {
    let r = try BalanceResponseParser.parseBalanceResponse(stringNumberJSON, endpoint: "/remaining")
    assertNearlyEqual(r.totalRemaining, 42.50, "String numbers totalRemaining")
    assertNearlyEqual(r.totalGranted, 100.00, "String numbers totalGranted")
    print("✅ String numbers: pass")
}

func testIntNumbers() throws {
    let r = try BalanceResponseParser.parseBalanceResponse(intNumberJSON, endpoint: "/remaining")
    assertNearlyEqual(r.totalRemaining, 50.00, "Int numbers totalRemaining")
    assertNearlyEqual(r.totalGranted, 200.00, "Int numbers totalGranted")
    print("✅ Int numbers: pass")
}

// ── Runner ──

@main
enum TestRunner {
    static func main() {
        do {
            try testOpenRouter()
            try testDeepSeek()
            try testOpenAISubscription()
            try testOpenAICreditGrants()
            try testGenericBalance()
            try testSimpleRemaining()
            try testGenericQuota()
            try testInvalidJSON()
            try testOpenRouterNoLimit()
            try testStringNumbers()
            try testIntNumbers()
            print("\n🎉 All balance parser tests PASSED!")
        } catch {
            print("balance-parser-test-fail: unexpected error: \(error)")
            exit(1)
        }
    }
}
