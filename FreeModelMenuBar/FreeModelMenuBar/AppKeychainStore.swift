//
//  AppKeychainStore.swift
//  FreeModelMenuBar
//
//  主 App 的 API Key 专用 Keychain 封装。
//  替代已废弃的 KeychainHelper（静默失败 + 纯文本存在 UserDefaults 的问题）。
//  模式参考 CodexInjector/AuthLayer/KeychainStore。
//

import Foundation
import Security

/// 主 App 的 API Key Keychain 存储。
/// 每个账号有唯一的 `apiKeyKeychainID`（在 ProviderAccount 中持久化），
/// 用该 ID 作为 Keychain attribute account 存取对应的 API Key。
public struct AppKeychainStore {
    public let service: String

    public init(service: String = "com.freemodel.menu-bar.apikeys") {
        self.service = service
    }

    /// 保存 API Key。若已存在则更新，不存在则新增。
    public func save(apiKey: String, account: String) throws {
        guard let data = apiKey.data(using: .utf8) else {
            throw AppKeychainError.invalidInput
        }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        var attrs = baseQuery
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attrs as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw AppKeychainError.osStatus(addStatus, "SecItemAdd")
            }
        default:
            throw AppKeychainError.osStatus(updateStatus, "SecItemUpdate")
        }
    }

    /// 读取 API Key。不存在时返回 nil。
    public func load(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw AppKeychainError.osStatus(status, "SecItemCopyMatching")
        }
    }

    /// 删除 API Key。
    public func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppKeychainError.osStatus(status, "SecItemDelete")
        }
    }
}

public enum AppKeychainError: Error, LocalizedError {
    case osStatus(OSStatus, String)
    case invalidInput

    public var errorDescription: String? {
        switch self {
        case .osStatus(let s, let op):
            let msg = SecCopyErrorMessageString(s, nil) as String? ?? "unknown"
            return "\(op) failed: \(s) (\(msg))"
        case .invalidInput:
            return "API Key 不是有效的 UTF-8 字符串"
        }
    }
}
