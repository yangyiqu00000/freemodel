import Foundation

extension TOMLTable {
    public static func == (lhs: TOMLTable, rhs: TOMLTable) -> Bool {
        guard lhs.storage.count == rhs.storage.count else { return false }
        // 顺序无关的语义等价比较：作为 table 时不关心 key 顺序
        for (k, lv) in lhs.storage {
            guard let rv = rhs.storage.first(where: { $0.0 == k })?.1 else { return false }
            if lv != rv { return false }
        }
        return true
    }
}
