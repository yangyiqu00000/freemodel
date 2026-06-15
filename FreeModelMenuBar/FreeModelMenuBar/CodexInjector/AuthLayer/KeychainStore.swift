import Foundation
import Security

/// macOS Keychain 封装。
/// 行为：把 AuthCredential 整体 JSON 化后存到一个通用密码项里。
/// 这样做的好处是：
///   1. 一条记录就是一个完整账号，删除/列出都简单；
///   2. 不需要定义一组固定的 Keychain attributes，结构演进零成本。
public struct KeychainStore {
    public let service: String
    public let accessGroup: String?

    public init(
        service: String = "local.codex.injector.auth",
        accessGroup: String? = nil
    ) {
        self.service = service
        self.accessGroup = accessGroup
    }

    public func save(_ credential: AuthCredential, account: String) throws {
        let data = try JSONEncoder.iso8601.encode(credential)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        var attrs: [String: Any] = baseQuery
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attrs as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.osStatus(addStatus, "SecItemAdd")
            }
        default:
            throw KeychainError.osStatus(updateStatus, "SecItemUpdate")
        }
    }

    public func load(account: String) throws -> AuthCredential? {
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
            return try JSONDecoder.iso8601.decode(AuthCredential.self, from: data)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.osStatus(status, "SecItemCopyMatching")
        }
    }

    public func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.osStatus(status, "SecItemDelete")
        }
    }

    public func listAccounts() throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)
        switch status {
        case errSecSuccess:
            let array = items as? [[String: Any]] ?? []
            return array.compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
        case errSecItemNotFound:
            return []
        default:
            throw KeychainError.osStatus(status, "SecItemCopyMatching(list)")
        }
    }
}

public enum KeychainError: Error, CustomStringConvertible {
    case osStatus(OSStatus, String)

    public var description: String {
        switch self {
        case .osStatus(let s, let op):
            let msg = SecCopyErrorMessageString(s, nil) as String? ?? "unknown"
            return "\(op) failed: \(s) (\(msg))"
        }
    }
}
