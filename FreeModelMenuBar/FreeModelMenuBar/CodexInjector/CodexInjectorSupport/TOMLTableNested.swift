import Foundation

extension TOMLTable {
    /// 在 key path 末端的 table 上设置 key = value。
    /// 自动补齐中间表。递归地修改 self.storage。
    public mutating func setValue(_ value: TOMLValue, at keyPath: String) {
        let parts = keyPath.split(separator: ".").map(String.init)
        guard let last = parts.last else { return }
        if parts.count == 1 {
            self[last] = value
            return
        }
        // 在 self.storage 上递归向下走
        recursiveSet(&self.storage, parts: parts, lastIndex: parts.count - 1, value: value, lastKey: last)
    }

    private func recursiveSet(
        _ storage: inout [(String, TOMLValue)],
        parts: [String],
        lastIndex: Int,
        value: TOMLValue,
        lastKey: String
    ) {
        guard !parts.isEmpty else { return }
        let seg = parts[0]
        let rest = Array(parts.dropFirst())
        // 找到 seg
        if let idx = storage.firstIndex(where: { $0.0 == seg }) {
            if rest.isEmpty {
                // 这是最后一段
                storage[idx] = (seg, value)
                return
            }
            // 进入子表
            if case .table(var sub) = storage[idx].1 {
                recursiveSet(&sub.storage, parts: rest, lastIndex: lastIndex - 1, value: value, lastKey: lastKey)
                storage[idx] = (seg, .table(sub))
            } else {
                // 冲突：覆盖为新表
                var newSub = TOMLTable()
                recursiveSet(&newSub.storage, parts: rest, lastIndex: lastIndex - 1, value: value, lastKey: lastKey)
                storage[idx] = (seg, .table(newSub))
            }
        } else {
            // 不存在：插入新表
            if rest.isEmpty {
                storage.append((seg, value))
                return
            }
            var newSub = TOMLTable()
            recursiveSet(&newSub.storage, parts: rest, lastIndex: lastIndex - 1, value: value, lastKey: lastKey)
            storage.append((seg, .table(newSub)))
        }
    }

    /// 沿 key path 读取值（多段点分路径）
    public func value(at keyPath: String) -> TOMLValue? {
        let parts = keyPath.split(separator: ".").map(String.init)
        var current: TOMLValue? = nil
        for (i, part) in parts.enumerated() {
            if i == 0 {
                current = self[part]
            } else {
                guard case .table(let sub) = current ?? .table(TOMLTable()) else { return nil }
                current = sub[part]
            }
        }
        return current
    }
}
