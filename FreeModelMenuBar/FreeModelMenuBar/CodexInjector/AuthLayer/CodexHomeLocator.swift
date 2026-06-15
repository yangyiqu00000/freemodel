import Foundation

/// 解析 `~/.codex` 路径。
/// 优先：
///   1. 显式传入
///   2. 环境变量 `CODEX_HOME`
///   3. `~/.codex`
public enum CodexHomeLocator {
    public static func resolve(override: URL? = nil) -> URL {
        if let override { return override }
        if let env = ProcessInfo.processInfo.environment["CODEX_HOME"], !env.isEmpty {
            return URL(fileURLWithPath: (env as NSString).expandingTildeInPath)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".codex")
    }

    public static func ensureExists(_ url: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
