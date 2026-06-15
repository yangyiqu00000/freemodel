import Foundation

/// 极简 TOML 模型，目标是能 round-trip Codex 桌面端期望的 config.toml 子集：
///   - 顶层或嵌套的 string / int / double / bool
///   - 数组（基础类型数组）
///   - 表（嵌套字典）
///
/// 暂不支持：日期（写成 RFC3339 字符串）、多行字符串、字面量字符串（我们只输出双引号转义）、
/// 数组的表（`[[foo]]`）——后者跟我们的注入模型无关。
public indirect enum TOMLValue: Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([TOMLValue])
    case table(TOMLTable)

    public static func == (lhs: TOMLValue, rhs: TOMLValue) -> Bool {
        switch (lhs, rhs) {
        case (.string(let a), .string(let b)): return a == b
        case (.int(let a), .int(let b)): return a == b
        case (.double(let a), .double(let b)): return a == b
        case (.bool(let a), .bool(let b)): return a == b
        case (.array(let a), .array(let b)): return a == b
        case (.table(let a), .table(let b)): return a == b
        default: return false
        }
    }
}

public struct TOMLTable: Equatable, Sendable {
    public var storage: [(String, TOMLValue)] = []

    public init(_ pairs: [(String, TOMLValue)] = []) {
        self.storage = pairs
    }

    public init(dictionary: [String: TOMLValue]) {
        // 用 sorted key 来稳定输出
        self.storage = dictionary.sorted { $0.key < $1.key }
    }

    public var keys: [String] { storage.map(\.0) }

    public var keysSet: Set<String> { Set(keys) }

    public var count: Int { storage.count }

    public subscript(key: String) -> TOMLValue? {
        get { storage.first(where: { $0.0 == key })?.1 }
        set {
            if let v = newValue {
                if let idx = storage.firstIndex(where: { $0.0 == key }) {
                    storage[idx] = (key, v)
                } else {
                    storage.append((key, v))
                }
            } else {
                storage.removeAll { $0.0 == key }
            }
        }
    }

    public mutating func removeValue(forKey key: String) {
        storage.removeAll { $0.0 == key }
    }

    public var dictionary: [String: TOMLValue] {
        Dictionary(uniqueKeysWithValues: storage)
    }
}

public extension TOMLValue {
    /// 提取 string 值（不是 string 时返回 nil）
    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
    /// 提取 int 值
    var intValue: Int? {
        if case .int(let i) = self { return i }
        return nil
    }
    /// 提取 double 值
    var doubleValue: Double? {
        if case .double(let d) = self { return d }
        return nil
    }
    /// 提取 bool 值
    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
    /// 提取 table 值
    var tableValue: TOMLTable? {
        if case .table(let t) = self { return t }
        return nil
    }
    /// 提取数组值
    var arrayValue: [TOMLValue]? {
        if case .array(let a) = self { return a }
        return nil
    }
}
