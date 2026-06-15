import Foundation

/// 把 `TOMLTable` 序列化成 TOML 文本。
/// 输出风格：双引号字符串、保留 key 插入顺序（不是排序后的），表用 `[parent.child]`。
public struct TOMLSerializer {
    public init() {}

    public func serialize(table: TOMLTable) -> String {
        var out = ""
        // 顶层先打 scalar / 数组
        for (key, value) in table.storage {
            renderScalar(parentPath: "", key: key, value: value, into: &out)
        }
        // 再打表（顶层或嵌套），按路径排序保证可读性
        let tablePaths = collectTablePaths(in: table, prefix: "")
        for path in tablePaths.sorted() {
            out += "\n[\(path)]\n"
            if let sub = lookup(table: table, path: path) {
                for (k, v) in sub.storage {
                    renderScalar(parentPath: path, key: k, value: v, into: &out)
                }
            }
        }
        return out
    }

    private func renderScalar(parentPath: String, key: String, value: TOMLValue, into out: inout String) {
        switch value {
        case .table:
            return // 由外层按路径处理
        case .array(let arr):
            out += "\(key) = \(formatArray(arr))\n"
        default:
            out += "\(key) = \(formatScalar(value))\n"
        }
    }

    private func formatScalar(_ v: TOMLValue) -> String {
        switch v {
        case .string(let s): return quote(s)
        case .int(let i): return String(i)
        case .double(let d):
            // TOML 接受整数形式的小数，但我们保险一点输出小数
            if d.rounded() == d && abs(d) < 1e15 {
                return String(format: "%.1f", d)
            }
            return String(d)
        case .bool(let b): return b ? "true" : "false"
        case .array(let a): return formatArray(a)
        case .table: return "/* table */"
        }
    }

    private func formatArray(_ arr: [TOMLValue]) -> String {
        let parts = arr.map { formatScalar($0) }
        return "[" + parts.joined(separator: ", ") + "]"
    }

    private func quote(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    private func collectTablePaths(in table: TOMLTable, prefix: String) -> [String] {
        var paths: [String] = []
        for (key, value) in table.storage {
            guard case .table(let sub) = value else { continue }
            let path = prefix.isEmpty ? key : "\(prefix).\(key)"
            paths.append(path)
            paths.append(contentsOf: collectTablePaths(in: sub, prefix: path))
        }
        return paths
    }

    private func lookup(table: TOMLTable, path: String) -> TOMLTable? {
        var current: TOMLTable = table
        for key in path.split(separator: ".").map(String.init) {
            guard
                case .table(let next) = current[key] ?? .table(TOMLTable())
            else { return nil }
            current = next
        }
        return current
    }
}
