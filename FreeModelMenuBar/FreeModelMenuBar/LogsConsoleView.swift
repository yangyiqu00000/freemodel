import SwiftUI

struct LogsConsoleView: View {
    @ObservedObject var routerManager: RouterManager
    @ObservedObject var accountManager: AccountManager

    @State private var logsClearedToast: String?
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
            }

            if let activeAccount = accountManager.activeAccount {
                let settings = activeAccount.activeRouterSettings
                HStack(alignment: .top, spacing: Spacing.loose) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("账号")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(activeAccount.displayName)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    if settings.enabled && routerManager.status.isRunning {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("监听")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(routerBaseURL(settings.port))
                                .font(.app(.monoCaption))
                                .textSelection(.enabled)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("上游")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(settings.upstreamBaseURL)
                                .font(.app(.monoCaption))
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
            HStack(spacing: Spacing.relaxed) {
                Button(action: copyAllLogs) {
                    Label("复制日志", systemImage: "doc.on.doc.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .uniformButtonHeight()
                .disabled(routerManager.logs.isEmpty)

                Button(action: clearLogsWithToast) {
                    Label("清除日志", systemImage: "trash.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .uniformButtonHeight()
                .disabled(routerManager.logs.isEmpty)

                toastBadge(value: logsClearedToast, icon: "trash.fill", tint: .secondary)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("控制台输出 (最近 \(RouterManager.maxLogCount) 条)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.tight) {
                        if routerManager.logs.isEmpty {
                            Text("无日志数据")
                                .font(.app(.monoCaption))
                                .foregroundStyle(.gray)
                                .padding(.vertical, Spacing.standard)
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
                    .overlayScrollers()
                    .padding(Spacing.standard)
                }
                .frame(minHeight: 340, maxHeight: .infinity)
                .background(Color.codeBackground)
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
        ClipboardHelper.shared.copy(formatLog(log))
    }

    private func clearLogsWithToast() {
        let count = routerManager.logs.count
        routerManager.logs.removeAll()
        let message = count == 0 ? "当前无日志" : "已清除 \(count) 条日志"
        showToast(message, at: $logsClearedToast)
    }

    private func copyAllLogs() {
        // logs[0] 是最新一条，反转后保持时间正序输出到剪贴板
        let allLogs = routerManager.logs.reversed().map(formatLog).joined(separator: "\n")
        ClipboardHelper.shared.copy(allLogs)
    }

    // 日志行的可读字符串表示，单行/批量复制共用同一份格式
    private func formatLog(_ log: RouterLogEntry) -> String {
        let timeStr = "[\(log.time)]"
        let methodStr = log.method
        if log.method == "SYS" || log.method == "INFO" || log.method == "ERROR" {
            return "\(timeStr) \(methodStr): \(log.error ?? "")"
        }
        var mainLog = "\(timeStr) \(methodStr): \(log.path) \(log.status) (\(log.duration)ms) | \(log.model) -> \(log.upstream)"
        if let error = log.error {
            mainLog += " - Err: \(error)"
        }
        return mainLog
    }

    private func showToast<T: Equatable>(_ value: T?, at binding: Binding<T?>, seconds: Double = 3.0) {
        toastTask?.cancel()
        toastTask = scheduleToastDismiss(value: value, binding: binding, seconds: seconds)
    }
}
