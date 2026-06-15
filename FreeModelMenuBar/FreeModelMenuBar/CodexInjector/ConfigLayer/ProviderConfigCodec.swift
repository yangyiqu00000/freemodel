import Foundation

/// `Provider` <-> TOML `[model_providers.<id>]` 块的转换。
enum ProviderConfigCodec {
    /// 从 TOML 表里把指定 id 的 `[model_providers.<id>]` 解出来。
    static func extractProvider(from table: TOMLTable, id: String) -> Provider? {
        guard
            let providersTable = table["model_providers"]?.tableValue,
            let sub = providersTable[id]?.tableValue
        else { return nil }
        guard let displayName = sub["name"]?.stringValue else { return nil }
        guard
            let urlString = sub["base_url"]?.stringValue,
            let url = URL(string: urlString)
        else { return nil }
        let wire: Provider.WireAPI = {
            if let s = sub["wire_api"]?.stringValue {
                return Provider.WireAPI(rawValue: s) ?? .responses
            }
            return .responses
        }()
        let requiresAuth = sub["requires_openai_auth"]?.boolValue ?? true
        let authMode: Provider.AuthMode = requiresAuth ? .openaiBearer : .none
        let bearer = sub["experimental_bearer_token"]?.stringValue
        return Provider(
            id: id,
            displayName: displayName,
            baseURL: url,
            wireAPI: wire,
            authMode: authMode,
            bearerToken: bearer,
            notes: nil,
            createdAt: Date()
        )
    }

    /// 把单个 provider 写回（或替换）`[model_providers.<id>]` 块。
    static func upsertProvider(_ provider: Provider, in table: inout TOMLTable) {
        var providers = table["model_providers"]?.tableValue ?? TOMLTable()
        var sub = TOMLTable()
        sub["name"] = .string(provider.displayName)
        sub["base_url"] = .string(provider.baseURL.absoluteString)
        sub["wire_api"] = .string(provider.wireAPI.rawValue)
        sub["requires_openai_auth"] = .bool(provider.authMode == .openaiBearer)
        if let token = provider.bearerToken, !token.isEmpty {
            sub["experimental_bearer_token"] = .string(token)
        }
        providers[provider.id] = .table(sub)
        table["model_providers"] = .table(providers)
    }

    static func removeProvider(id: String, in table: inout TOMLTable) {
        guard var providers = table["model_providers"]?.tableValue else { return }
        providers.removeValue(forKey: id)
        if providers.count == 0 {
            table.removeValue(forKey: "model_providers")
        } else {
            table["model_providers"] = .table(providers)
        }
        if let s = table["model_provider"]?.stringValue, s == id {
            table.removeValue(forKey: "model_provider")
        }
    }
}
