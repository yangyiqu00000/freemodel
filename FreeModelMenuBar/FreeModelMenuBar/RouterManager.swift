//
//  RouterManager.swift
//  FreeModelMenuBar
//
//  Lifecycle management, state publishing, and logging for the local Responses proxy.
//

import Combine
import Foundation
import Network
import AppKit
import SwiftUI

enum RouterStatus: String, Codable, CaseIterable {
    case off = "已关闭"
    case starting = "启动中..."
    case running = "运行中"
    case failed = "启动失败"
    case portInUse = "端口占用"
    case missingKey = "未配置 Key"

    var subtitle: String {
        switch self {
        case .off: return "路由未启动"
        case .starting: return "路由启动中…"
        case .running: return "路由运行中"
        case .failed: return "路由启动失败"
        case .portInUse: return "端口占用"
        case .missingKey: return "请先配置 API Key"
        }
    }

    var statusColor: Color? {
        switch self {
        case .running: return .green
        case .starting: return .orange
        case .failed, .portInUse, .missingKey: return .red
        case .off: return nil
        }
    }
}

struct RouterLogEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    let time: String
    let method: String
    let path: String
    let status: Int
    let duration: Int
    let model: String
    let upstream: String
    let error: String?

    enum CodingKeys: String, CodingKey {
        case time, method, path, status, duration, model, upstream, error
    }
}

final class RouterManager: ObservableObject {
    @Published var status: RouterStatus = .off
    @Published var logs: [RouterLogEntry] = []

    private let accountManager: AccountManager
    private var runningProcess: Process?
    private var runningInputPipe: Pipe? = nil
    private var healthCheckTimer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private var outputBuffer = ""
    private var isStopping = false

    init(accountManager: AccountManager) {
        self.accountManager = accountManager

        killOrphanedProxies()

        // Sync and monitor active account's router settings
        accountManager.$activeAccountID
            .combineLatest(accountManager.$accounts)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.syncStateWithActiveAccount()
            }
            .store(in: &cancellables)

        registerNotifications()
    }

    deinit {
        stopProxy()
    }

    /// Sync proxy lifecycle with active account settings
    func syncStateWithActiveAccount() {
        guard !isStopping else {
            return
        }

        guard let activeAccount = accountManager.activeAccount else {
            stopProxy()
            return
        }

        let settings = activeAccount.activeRouterSettings

        if settings.enabled {
            // Check if we already run the correct configuration
            if let runningProcess = runningProcess, runningProcess.isRunning {
                let env = runningProcess.environment ?? [:]
                let currentPort = env["PORT"]

                if currentPort != String(settings.port) {
                    appendLog("监听端口已更改，正在重启路由代理服务...")
                    stopProxy { [weak self] in
                        self?.startProxy(for: activeAccount)
                    }
                } else {
                    // Send updated configuration to the running process dynamically
                    sendConfigToSidecar(activeAccount: activeAccount)
                }
            } else if status != .starting {
                startProxy(for: activeAccount)
            }
        } else {
            if runningProcess != nil {
                appendLog("路由代理已通过设置关闭。")
                stopProxy()
            } else {
                status = .off
            }
        }
    }

    /// Toggle router state manually
    func toggleRouter() {
        guard let activeAccount = accountManager.activeAccount else { return }
        var settings = activeAccount.activeRouterSettings
        settings.enabled.toggle()
        accountManager.updateRouterSettings(settings, for: activeAccount.id)
    }

    /// Start the local sidecar proxy
    func startProxy(for account: ProviderAccount) {
        let settings = account.activeRouterSettings

        // Validation 1: Upstream Key
        guard account.hasAPIKey, let apiKey = account.apiKey, !apiKey.isEmpty else {
            status = .missingKey
            appendLog("启动失败：当前账号未配置 API Key。")
            return
        }

        status = .starting
        appendLog("正在启动本地路由代理，监听端口: \(settings.port)...")

        // Validation 2: Port Availability with retry to allow OS to release socket
        checkPortAvailableWithRetry(port: settings.port, attempts: 5, delay: 0.2) { [weak self] available in
            guard let self = self else { return }
            guard available else {
                self.status = .portInUse
                self.appendLog("启动失败：本地端口 \(settings.port) 已被占用。")
                return
            }

            // Locate sidecar script
            guard let scriptPath = Bundle.main.path(forResource: "router_sidecar", ofType: "js") else {
                // Fallback for development/debug environments
                let devPath = "/Users/yyq/Library/Application Support/TRAE SOLO CN/ModularData/ai-agent/work-mode-projects/6a167704dad46ec56f2b1566/FreeModelMenuBar/FreeModelMenuBar/router_sidecar.js"
                if FileManager.default.fileExists(atPath: devPath) {
                    self.launchProcess(scriptPath: devPath, port: settings.port, apiKey: apiKey, settings: settings, activeAccount: account)
                } else {
                    self.status = .failed
                    self.appendLog("错误：未能在 App Bundle 或本地路径中找到 router_sidecar.js")
                }
                return
            }

            self.launchProcess(scriptPath: scriptPath, port: settings.port, apiKey: apiKey, settings: settings, activeAccount: account)
        }
    }

    private func locateNode() -> String? {
        // 1. Check typical absolute paths
        let commonPaths = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node"
        ]
        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // 2. Try to locate via zsh with zshrc sourced (for NVM/custom path users)
        let tempProcess = Process()
        tempProcess.executableURL = URL(fileURLWithPath: "/bin/zsh")
        tempProcess.arguments = ["-c", "source ~/.zshrc && which node"]
        
        let pipe = Pipe()
        tempProcess.standardOutput = pipe
        tempProcess.standardError = Pipe()
        
        do {
            try tempProcess.run()
            tempProcess.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty, FileManager.default.fileExists(atPath: output) {
                return output
            }
        } catch {
            // ignore
        }

        // 3. Fallback: try searching in ~/.nvm/versions/node/
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let nvmNodeDir = homeDir.appendingPathComponent(".nvm/versions/node")
        if let enumerator = FileManager.default.enumerator(at: nvmNodeDir, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator {
                if url.lastPathComponent == "node" {
                    return url.path
                }
            }
        }

        return nil
    }

    private func launchProcess(scriptPath: String, port: Int, apiKey: String, settings: RouterSettings, activeAccount: ProviderAccount) {
        guard let nodePath = locateNode() else {
            status = .failed
            appendLog("启动失败：未能在系统中找到 node 可执行程序。请确保已安装 Node.js")
            return
        }

        appendLog("找到 Node 执行路径: \(nodePath)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = [scriptPath]

        var env = ProcessInfo.processInfo.environment
        env["PORT"] = String(port)
        env["UPSTREAM_BASE_URL"] = settings.upstreamBaseURL
        env["UPSTREAM_API_KEY"] = apiKey
        env["UPSTREAM_MODEL"] = settings.defaultModel
        env["ROUTE_MODEL"] = settings.routeModel
        env["PROXY_MAX_CONCURRENCY"] = String(settings.maxConcurrency ?? 0)
        env["PROXY_MIN_INTERVAL_MS"] = String(settings.minIntervalMs ?? 0)
        env["PROXY_FAILOVER_ENABLED"] = settings.isFailoverEnabled ? "true" : "false"
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        let inPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = inPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let output = String(data: data, encoding: .utf8) {
                self?.handleProxyOutput(output)
            }
        }

        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let error = String(data: data, encoding: .utf8) {
                self?.handleProxyError(error)
            }
        }

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.appendLog("路由代理侧车进程已退出。")
                if self?.status == .running || self?.status == .starting {
                    self?.status = .failed
                }
                self?.runningProcess = nil
                self?.runningInputPipe = nil
            }
        }

        do {
            try process.run()
            self.runningProcess = process
            self.runningInputPipe = inPipe
            
            // Send full configuration (including backups) via stdin immediately
            sendConfigToSidecar(activeAccount: activeAccount)
            
            startHealthCheck(port: port)
        } catch {
            status = .failed
            appendLog("执行 node 进程失败: \(error.localizedDescription)")
        }
    }

    /// Stop the local sidecar proxy
    func stopProxy(completion: (() -> Void)? = nil) {
        healthCheckTimer?.cancel()
        healthCheckTimer = nil
        runningInputPipe = nil

        guard let process = runningProcess else {
            isStopping = false
            status = .off
            completion?()
            return
        }

        if process.isRunning {
            isStopping = true
            process.terminationHandler = { [weak self] _ in
                DispatchQueue.main.async {
                    self?.appendLog("路由代理侧车进程已退出。")
                    self?.runningProcess = nil
                    self?.runningInputPipe = nil
                    self?.isStopping = false
                    self?.status = .off
                    completion?()
                    self?.syncStateWithActiveAccount()
                }
            }
            process.terminate()
        } else {
            runningProcess = nil
            isStopping = false
            status = .off
            completion?()
        }
    }

    private func checkPortAvailable(port: Int) -> Bool {
        let socketFileDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        if socketFileDescriptor == -1 {
            return false
        }
        defer {
            close(socketFileDescriptor)
        }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFileDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        return bindResult == 0
    }

    private func checkPortAvailableWithRetry(port: Int, attempts: Int, delay: TimeInterval, completion: @escaping (Bool) -> Void) {
        if checkPortAvailable(port: port) {
            completion(true)
            return
        }

        if attempts <= 1 {
            completion(false)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.checkPortAvailableWithRetry(port: port, attempts: attempts - 1, delay: delay, completion: completion)
        }
    }

    private func startHealthCheck(port: Int) {
        healthCheckTimer?.cancel()

        var attempts = 0
        healthCheckTimer = Timer.publish(every: 0.3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                attempts += 1
                if attempts > 10 {
                    self?.status = .failed
                    self?.appendLog("健康自检超时：本地代理服务未能在 3 秒内响应。")
                    self?.stopProxy()
                    self?.healthCheckTimer?.cancel()
                    return
                }

                self?.performHealthCheckRequest(port: port) { success in
                    if success {
                        self?.status = .running
                        self?.appendLog("路由代理启动成功！监听地址: http://127.0.0.1:\(port)/v1")
                        self?.healthCheckTimer?.cancel()
                    }
                }
            }
    }

    private func performHealthCheckRequest(port: Int, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else {
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 0.2

        URLSession.shared.dataTask(with: request) { _, response, _ in
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                DispatchQueue.main.async {
                    completion(true)
                }
            } else {
                DispatchQueue.main.async {
                    completion(false)
                }
            }
        }.resume()
    }

    private func handleProxyOutput(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.outputBuffer += text
            let lines = self.outputBuffer.components(separatedBy: "\n")
            self.outputBuffer = lines.last ?? ""

            for line in lines.dropLast() {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }

                // Parse structured JSON log
                if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") {
                    if let data = trimmed.data(using: .utf8),
                       let entry = try? JSONDecoder().decode(RouterLogEntry.self, from: data) {
                        self.prependingLog(entry)
                        continue
                    }
                }

                // Append raw text logs (usually server startup output)
                if !trimmed.contains("Starting") && !trimmed.contains("listening") && !trimmed.contains("[Proxy]") {
                    continue
                }
                
                let rawEntry = RouterLogEntry(
                    time: Date().formatted(date: .omitted, time: .standard),
                    method: "INFO",
                    path: "",
                    status: 200,
                    duration: 0,
                    model: "",
                    upstream: "",
                    error: trimmed
                )
                self.prependingLog(rawEntry)
            }
        }
    }

    private func handleProxyError(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return }

            let rawEntry = RouterLogEntry(
                time: Date().formatted(date: .omitted, time: .standard),
                method: "ERROR",
                path: "",
                status: 500,
                duration: 0,
                model: "",
                upstream: "",
                error: trimmed
            )
            self.prependingLog(rawEntry)
        }
    }

    /// 插入一条日志到 logs 顶部，自动截断到最多 50 条
    private func prependingLog(_ entry: RouterLogEntry) {
        logs.insert(entry, at: 0)
        if logs.count > 50 {
            logs.removeLast()
        }
    }

    private func appendLog(_ message: String) {
        // 日志在 SwiftUI 的 @Published 数组上更新，需要在主线程操作。
        // 主线程直接写入以避免一次额外的 runloop 延迟（启动期连续日志尤为明显），
        // 后台线程（如 Pipe 读取回调）才走 dispatch。
        let write = { [weak self] in
            guard let self = self else { return }
            let entry = RouterLogEntry(
                time: Date().formatted(date: .omitted, time: .standard),
                method: "SYS",
                path: "",
                status: 200,
                duration: 0,
                model: "",
                upstream: "",
                error: message
            )
            self.prependingLog(entry)
        }
        if Thread.isMainThread {
            write()
        } else {
            DispatchQueue.main.async(execute: write)
        }
    }

    // MARK: - Notifications & Autorecover
    private func registerNotifications() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func handleWake() {
        appendLog("系统从休眠中唤醒，检测路由可用性...")
        guard let activeAccount = accountManager.activeAccount else { return }
        let settings = activeAccount.activeRouterSettings
        if settings.enabled {
            performHealthCheckRequest(port: settings.port) { [weak self] success in
                if !success {
                    self?.appendLog("检测到代理进程已断开，正在尝试自愈重启...")
                    self?.stopProxy {
                        self?.startProxy(for: activeAccount)
                    }
                } else {
                    self?.appendLog("检测成功：代理服务运行正常。")
                }
            }
        }
    }

    private func sendConfigToSidecar(activeAccount: ProviderAccount) {
        guard let pipe = runningInputPipe else {
            appendLog("发送配置失败：写入管道不可用。")
            return
        }

        let settings = activeAccount.activeRouterSettings

        // Collect backups
        var backupInfos: [[String: String]] = []
        let backupAccounts = accountManager.accounts.filter {
            $0.id != activeAccount.id &&
            $0.hasAPIKey &&
            !($0.apiKey ?? "").isEmpty
        }
        for p in backupAccounts {
            let backupSettings = p.activeRouterSettings
            backupInfos.append([
                "providerID": p.providerID,
                "url": backupSettings.upstreamBaseURL,
                "key": p.apiKey ?? "",
                "model": backupSettings.defaultModel
            ])
        }

        // Construct dictionary
        let msg: [String: Any] = [
            "type": "update_config",
            "activeAccount": [
                "providerID": activeAccount.providerID,
                "url": settings.upstreamBaseURL,
                "key": activeAccount.apiKey ?? "",
                "model": settings.defaultModel
            ],
            "backups": backupInfos,
            "routeModel": settings.routeModel,
            "maxConcurrency": settings.maxConcurrency ?? 0,
            "minIntervalMs": settings.minIntervalMs ?? 0,
            "failoverEnabled": settings.isFailoverEnabled
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: msg, options: [])
            if var jsonString = String(data: data, encoding: .utf8) {
                jsonString.append("\n")
                if let stringData = jsonString.data(using: .utf8) {
                    try? pipe.fileHandleForWriting.write(contentsOf: stringData)
                    appendLog("已通过管道动态更新代理配置 (备选渠道数: \(backupInfos.count))")
                }
            }
        } catch {
            appendLog("序列化动态配置 JSON 失败: \(error.localizedDescription)")
        }
    }

    private func killOrphanedProxies() {
        let pkillURL = URL(fileURLWithPath: "/usr/bin/pkill")
        guard FileManager.default.fileExists(atPath: pkillURL.path) else { return }
        let task = Process()
        task.executableURL = pkillURL
        task.arguments = ["-f", "router_sidecar.js"]
        try? task.run()
        task.waitUntilExit()
    }
}
