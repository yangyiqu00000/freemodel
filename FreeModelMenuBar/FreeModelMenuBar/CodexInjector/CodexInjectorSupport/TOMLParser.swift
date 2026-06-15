import Foundation

/// 把 TOML 文本解析成 `TOMLTable`。
/// 解析范围：与我们写入的范围一致。
/// 支持：
///   - 顶层或嵌套 k = v（标量、数组、字符串）
///   - [section] 跳到对应嵌套表（点分路径）
public struct TOMLParser {
    public init() {}

    public enum ParseError: Error, CustomStringConvertible {
        case syntax(String)
        public var description: String {
            switch self { case .syntax(let m): return "TOML syntax: \(m)" }
        }
    }

    public func parse(_ text: String) throws -> TOMLTable {
        // 按行扫描：每行要么是 [section]、要么是 k = v、要么空/注释
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var root = TOMLTable()
        var currentPath: [String] = []

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            if line.hasPrefix("[") {
                guard line.hasSuffix("]") else {
                    throw ParseError.syntax("bad section header: \(line)")
                }
                let inner = String(line.dropFirst().dropLast())
                currentPath = inner.split(separator: ".").map(String.init)
                // 强制把路径上每一层都建成 table
                for i in 1...currentPath.count {
                    let prefix = currentPath[0..<i].joined(separator: ".")
                    if root.value(at: prefix) == nil {
                        root.setValue(.table(TOMLTable()), at: prefix)
                    }
                }
                continue
            }

            // k = v
            guard let eq = line.firstIndex(of: "=") else {
                throw ParseError.syntax("missing '=': \(line)")
            }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let valueStr = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            let value = try parseValue(valueStr)
            let keyPath = currentPath.isEmpty ? key : currentPath.joined(separator: ".") + "." + key
            root.setValue(value, at: keyPath)
        }

        return root
    }

    private func parseValue(_ s: String) throws -> TOMLValue {
        if s.isEmpty { throw ParseError.syntax("empty value") }
        if s.hasPrefix("\"") && s.hasSuffix("\"") && s.count >= 2 {
            let inner = String(s.dropFirst().dropLast())
            return .string(unescape(inner))
        }
        if s.hasPrefix("[") && s.hasSuffix("]") {
            let inner = String(s.dropFirst().dropLast())
            let parts = try splitArray(inner)
            let items = try parts.map { try parseValue($0) }
            return .array(items)
        }
        if s == "true" { return .bool(true) }
        if s == "false" { return .bool(false) }
        if let i = Int(s) { return .int(i) }
        if let d = Double(s) { return .double(d) }
        throw ParseError.syntax("unrecognized value: \(s)")
    }

    private func splitArray(_ s: String) throws -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var inString = false
        var escape = false
        for c in s {
            if escape { current.append(c); escape = false; continue }
            if c == "\\" && inString { current.append(c); escape = true; continue }
            if c == "\"" { inString.toggle(); current.append(c); continue }
            if !inString {
                if c == "[" { depth += 1 }
                if c == "]" { depth -= 1 }
                if c == "," && depth == 0 {
                    parts.append(current.trimmingCharacters(in: .whitespaces))
                    current = ""
                    continue
                }
            }
            current.append(c)
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append(current.trimmingCharacters(in: .whitespaces))
        }
        return parts
    }

    private func unescape(_ s: String) -> String {
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "\\" {
                let next = s.index(after: i)
                if next < s.endIndex {
                    switch s[next] {
                    case "n": out.append("\n")
                    case "t": out.append("\t")
                    case "\"": out.append("\"")
                    case "\\": out.append("\\")
                    default: out.append(s[next])
                    }
                    i = s.index(after: next)
                    continue
                }
            }
            out.append(c)
            i = s.index(after: i)
        }
        return out
    }
}
