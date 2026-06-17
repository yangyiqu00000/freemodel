import SwiftUI

struct LogsConsoleView: View {
    @ObservedObject var routerManager: RouterManager
    @ObservedObject var accountManager: AccountManager

    @State private var logsClearedToast: String?
    @State private var baseURLCopiedToast: String?
    @State private var toastTask: Task<Void, Never>?

    var body: some View {
        logsHeader
        logsConsoleSection
    }

    private var logsHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                navHeader(
                    icon: "terminal.fill",
                    tint: .green,
                    title: "路由代理运行日志",
                    subtitle: routerManager.status.subtitle,
                    dotColor: routerManager.status.statusColor
                )
                if let activeAccount = accountManager.activeAccount {
                    let isRunning = routerManager.status == .running
                    let portVal = activeAccount.activeRouterSettings.port
                    let urlString = "http://127.0.0.1:\(portVal)/v1"
                    Button(action: {
                        ClipboardHelper.shared.copy(urlString)
                        showToast("Base URL 已复制", at: $baseURLCopiedToast)
                    }) {
                        Label("复制 Base URL", systemImage: "doc.on.doc.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!isRunning)
                    .help(isRunning ? "复制 \(urlString) 到剪贴板" : "启动路由代理后才可复制 Base URL")
                    toastBadge(value: baseURLCopiedToast, icon: "doc.on.doc.fill", tint: .blue)
                }
            }

            if let activeAccount = accountManager.activeAccount {
                let settings = activeAccount.activeRouterSettings
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("账号")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(activeAccount.displayName)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    if settings.enabled && routerManager.status == .running {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("监听")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("http://127.0.0.1:\(settings.port)/v1")
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("上游")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(settings.upstreamBaseURL)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                    }
                    Spacer()
                }
                .font(.caption)
            } else {
                Text("请先添加并激活一个账号以配置和启动路由。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var logsConsoleSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Button(action: copyAllLogs) {
                    Label("复制所有日志", systemImage: "doc.on.doc.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .frame(height: 28)
                .disabled(routerManager.logs.isEmpty)

                Button(action: clearLogsWithToast) {
                    Label("清除日志", systemImage: "trash.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .frame(height: 28)
                .disabled(routerManager.logs.isEmpty)

                toastBadge(value: logsClearedToast, icon: "trash.fill", tint: .secondary)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("控制台输出 (最近 50 条)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if routerManager.logs.isEmpty {
                            Text("无日志数据")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.gray)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(routerManager.logs) { log in
                                LogRowView(log: log)
                                    .contextMenu {
                                        Button("复制此行") { copySingleLog(log) }
                                        if let err = log.error, !err.isEmpty {
                                            Button("复制错误详情") { ClipboardHelper.shared.copy(err) }
                                        }
                                    }
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(minHeight: 340, maxHeight: .infinity)
                .background(Color.black)
                .cornerRadius(6)
                .textSelection(.enabled)
            }
        }
    }

    private struct LogRowView: View {
        let log: RouterLogEntry

        var body: some View {
            let color: Color
            if log.method == "SYS" || log.method == "INFO" {
                color = .blue
            } else if log.method == "ERROR" {
                color = .red
            } else {
                color = log.status >= 400 ? .orange : .green
            }

            return HStack(alignment: .top, spacing: 6) {
                Text("[\(log.time)]")
                    .foregroundStyle(.gray)
                Text(log.method)
                    .fontWeight(.bold)
                    .foregroundStyle(color)
                    .frame(width: 45, alignment: .leading)
                if log.method == "SYS" || log.method == "INFO" || log.method == "ERROR" {
                    Text(log.error ?? "")
                        .foregroundStyle(.white)
                } else {
                    Text("\(log.path) \(log.status) (\(log.duration)ms) | \(log.model) -> \(log.upstream)")
                        .foregroundStyle(.white)
                    if let error = log.error {
                        Text("- Err: \(error)")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .font(.app(.logMono))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func copySingleLog(_ log: RouterLogEntry) {
        let text: String
        let timeStr = "[\(log.time)]"
        let methodStr = log.method
        if log.method == "SYS" || log.method == "INFO" || log.method == "ERROR" {
            text = "\(timeStr) \(methodStr): \(log.error ?? "")"
        } else {
            var mainLog = "\(timeStr) \(methodStr): \(log.path) \(log.status) (\(log.duration)ms) | \(log.model) -> \(log.upstream)"
            if let error = log.error {
                mainLog += " - Err: \(error)"
            }
            text = mainLog
        }
        ClipboardHelper.shared.copy(text)
    }

    private func clearLogsWithToast() {
        let count = routerManager.logs.count
        routerManager.logs.removeAll()
        let message = count == 0 ? "当前无日志" : "已清除 \(count) 条日志"
        showToast(message, at: $logsClearedToast)
    }

    private func copyAllLogs() {
        let logTexts = routerManager.logs.reversed().map { log -> String in
            let timeStr = "[\(log.time)]"
            let methodStr = log.method
            if log.method == "SYS" || log.method == "INFO" || log.method == "ERROR" {
                return "\(timeStr) \(methodStr): \(log.error ?? "")"
            } else {
                var mainLog = "\(timeStr) \(methodStr): \(log.path) \(log.status) (\(log.duration)ms) | \(log.model) -> \(log.upstream)"
                if let error = log.error {
                    mainLog += " - Err: \(error)"
                }
                return mainLog
            }
        }
        let allLogs = logTexts.joined(separator: "\n")
        ClipboardHelper.shared.copy(allLogs)
    }

    private func showToast<T: Equatable>(_ value: T?, at binding: Binding<T?>, seconds: Double = 3.0) {
        toastTask?.cancel()
        withAnimation { binding.wrappedValue = value }
        guard value != nil else { return }
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation { binding.wrappedValue = nil }
        }
    }
}
