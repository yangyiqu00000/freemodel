//
//  MenuContent.swift
//  FreeModelMenuBar
//
//  菜单栏下拉菜单内容
//

import SwiftUI

struct MenuContent: View {
    @EnvironmentObject var accountManager: AccountManager
    @EnvironmentObject var balanceManager: BalanceManager
    @EnvironmentObject var routerManager: RouterManager

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏：图标 + 标题 + 副标题（账号 / Codex 注入统计）
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 1) {
                    Text("FreeModel")
                        .font(.headline)
                    Text(headerSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if let activeAccount = accountManager.activeAccount {
                    Text(activeAccount.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if accountManager.accounts.count > 1 {
                sectionDivider()
                accountSwitcher
            }

            sectionDivider()

            if accountManager.activeAccount == nil {
                noAccountView
            } else if !balanceManager.isConfigured {
                // 未配置状态
                unconfiguredView
            } else if let balance = balanceManager.balanceInfo {
                // 已配置且有余额数据
                balanceDetailView(balance: balance)
            } else if balanceManager.isLoading {
                // 加载中
                loadingView
            } else {
                // 有错误
                errorView
            }

            // 本地路由卡片 (如果账号支持 API Key 查询或者开启了路由)
            if let account = accountManager.activeAccount, account.queryMode == .apiKey || account.activeRouterSettings.enabled {
                sectionDivider()
                routerStatusCard(account: account)
            }

            sectionDivider()

            // 操作按钮
            HStack(spacing: 12) {
                Button(action: {
                    Task { await balanceManager.fetchBalance() }
                }) {
                    Label("刷新", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .disabled(balanceManager.isLoading)

                Button(action: {
                    SettingsWindowController.shared.openSettings(
                        balanceManager: balanceManager,
                        accountManager: accountManager,
                        routerManager: routerManager
                    )
                }) {
                    Label("设置", systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }

                Button(action: {
                    if let url = URL(string: "https://freemodel.dev") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Label("官网", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .controlSize(.small)
            .buttonStyle(.bordered)

            Divider()

            // 底部信息
            HStack {
                if let lastRefresh = balanceManager.lastRefreshDate {
                    Text("上次更新: \(lastRefresh.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("自动刷新: \(Int(balanceManager.refreshInterval / 60))分钟")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 320)
    }

    // MARK: - 标题栏副标题

    private var headerSubtitle: String {
        let accountCount = accountManager.accounts.count
        let accountPart = accountCount == 0 ? "无账号" : "\(accountCount) 个账号"
        return "v1 · \(accountPart)"
    }

    // MARK: - 子视图

    private var accountSwitcher: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("账号")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)

            ForEach(accountManager.accounts) { account in
                let isActive = (account.id == accountManager.activeAccountID)
                Button {
                    accountManager.selectAccount(id: account.id)
                    balanceManager.syncFromActiveAccount()
                } label: {
                    HStack {
                        Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isActive ? .blue : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.displayName)
                                .lineLimit(1)
                                .fontWeight(isActive ? .semibold : .regular)
                            switch account.queryMode {
                            case .dashboard:
                                Text(account.hasDashboardSession ? "已保存控制台登录态" : "未登录控制台")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            case .apiKey:
                                Text(account.hasAPIKey ? "已保存 API Key" : "未配置 API Key")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let balance = account.lastBalance {
                            Text(balance.remainingFormatted)
                                .font(.caption)
                                .foregroundStyle(balance.isLow ? .orange : .green)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isActive ? Color.accentFill : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var noAccountView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.app(.displayNumber))
                .foregroundStyle(.orange)

            Text("还没有任何账号")
                .font(.headline)

            Text("点击「设置」添加账号")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }

    private var unconfiguredView: some View {
        VStack(spacing: 12) {
            if let account = accountManager.activeAccount {
                if account.queryMode == .dashboard {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .font(.app(.displayNumber))
                        .foregroundStyle(.orange)

                    Text("尚未登录控制台")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text("点击「设置」为当前账号登录 FreeModel 控制台")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Image(systemName: "key.fill")
                        .font(.app(.displayNumber))
                        .foregroundStyle(.orange)

                    Text("尚未配置 API Key")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text("点击「设置」输入并保存您的 API Key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                noAccountView
            }
        }
        .padding(24)
    }

    private func balanceDetailView(balance: BalanceInfo) -> some View {
        VStack(spacing: 16) {
            // 余额显示
            VStack(spacing: 4) {
                Text("剩余额度")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(balance.remainingFormatted)
                    .font(.app(.displayNumber))
                    .foregroundStyle(balance.isExhausted ? .red : balance.isLow ? .orange : .green)

                if balance.isLow && !balance.isExhausted {
                    Text("⚠️ 额度不足")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if balance.isExhausted {
                    Text("❌ 额度已用完")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.top, 8)

            // 使用进度条
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("已使用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(String(format: "%.1f", balance.usagePercentage))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [progressColor(percentage: balance.usagePercentage), progressColor(percentage: balance.usagePercentage).opacity(0.7)]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, geo.size.width * min(balance.usagePercentage / 100, 1)), height: 8)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text("已用: \(balance.usedFormatted)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("总额: \(balance.totalFormatted)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // 过期时间
            if let expiresAt = balance.expiresAt {
                HStack {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("过期时间: \(expiresAt.formatted(date: .numeric, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            Text("正在查询余额...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }

    private var errorView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.red)

            if let error = balanceManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("重试") {
                Task { await balanceManager.fetchBalance() }
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
    }

    // MARK: - 辅助方法

    private func progressColor(percentage: Double) -> Color {
        if percentage > 90 {
            return .red
        } else if percentage > 70 {
            return .orange
        } else {
            return .green
        }
    }

    // MARK: - Router status views

    private func statusBadge(_ status: RouterStatus) -> some View {
        let color: Color
        switch status {
        case .off: color = .gray
        case .starting: color = .orange
        case .running: color = .green
        case .failed: color = .red
        case .portInUse: color = .red
        case .missingKey: color = .red
        }

        return Text(status.rawValue)
            .font(.app(.microLabel))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .foregroundStyle(.white)
            .background(RoundedRectangle(cornerRadius: 3).fill(color))
    }

    private func routerStatusCard(account: ProviderAccount) -> some View {
        let settings = account.activeRouterSettings
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("本地 Responses 路由", systemImage: "arrow.triangle.2.circlepath.circle")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                statusBadge(routerManager.status)
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("监听地址:")
                        .font(.app(.microTag))
                        .foregroundStyle(.secondary)
                    Text(routerBaseURL(settings.port))
                        .font(.app(.microTag))
                        .foregroundStyle(.blue)
                }
                Spacer()
                
                Button(action: {
                    routerManager.toggleRouter()
                }) {
                    Text(settings.enabled ? "停止" : "启动")
                        .font(.app(.microLabel))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 3).fill(settings.enabled ? Color.red : Color.blue))
                }
                .buttonStyle(.plain)
                .disabled(!account.hasAPIKey)
                
                if routerManager.status.isRunning {
                    Button(action: {
                        ClipboardHelper.shared.copy(routerBaseURL(settings.port))
                    }) {
                        Image(systemName: "doc.on.doc.fill")
                            .font(.app(.microTag))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.08)))
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }
}
