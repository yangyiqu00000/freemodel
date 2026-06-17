//
//  KeychainHelper.swift
//  FreeModelMenuBar
//
//  安全存储 API Key 到 macOS Keychain
//

import Foundation
import Security

final class KeychainHelper {
    static let shared = KeychainHelper()
    private init() {}

    // Keychain 服务标识（3 处 query 字典共用）。集中后改 bundle id 不会漏。
    private static let service = "com.freemodel.menu bar"

    func save(key: String, value: String) {
        // 先删除已有的
        delete(key: key)

        guard let data = value.data(using: .utf8) else {
            print("Keychain save error: value is not valid UTF-8")
            return
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrService as String: Self.service,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("Keychain save error: \(status)")
        }
    }

    func get(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: Self.service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: Self.service
        ]

        SecItemDelete(query as CFDictionary)
    }
}
