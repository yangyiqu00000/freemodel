import Foundation

/// 跨层共享的文件系统工具。
public enum FileSystemSupport {
    /// 原子写文件：先写同目录临时文件，再 rename 到目标路径。
    /// Codex 桌面端会监听 `~/.codex/auth.json` 和 `config.toml`，原子写避免读到半截状态。
    public static func atomicWrite(data: Data, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = dir.appendingPathComponent(".\(url.lastPathComponent).tmp.\(UUID().uuidString)")
        try data.write(to: tmp, options: .atomic)
        // 覆盖式 rename
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: url)
        }
    }
}

extension JSONEncoder {
    public static let iso8601: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}

extension JSONDecoder {
    public static let iso8601: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
