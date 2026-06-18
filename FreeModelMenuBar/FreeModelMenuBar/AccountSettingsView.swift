import SwiftUI

struct AccountSettingsView: View {
    let accountID: UUID
    @ObservedObject var accountManager: AccountManager
    @ObservedObject var balanceManager: BalanceManager
    @ObservedObject var routerManager: RouterManager
    @Binding var pendingScrollToAPIKey: Bool

    private var account: ProviderAccount? {
        accountManager.account(id: accountID)
    }

    @State private var renameText: String = ""
    @State private var initialDisplayName: String = ""

    // renameText 修剪后值，body 内多次复用避免重复 trimmingCharacters 扫描
    private var trimmedRenameText: String {
        renameText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum ApiKeyStatus: Equatable {
        case empty, unsaved, testing, verified, failed(String), saved

        // 用户编辑输入时调用：若当前是已验证/已保存，则回到未保存状态（TextField/SecureField 4 处共用）
        mutating func markUnsavedIfPersisted() {
            switch self {
            case .verified, .saved:
                self = .unsaved
            default:
                break
            }
        }
    }
    @State private var apiKeyStatus: ApiKeyStatus = .empty
    @State private var apiKeyInput: String = ""
    @State private var showAPIKey: Bool = false
    @State private var isTesting: Bool = false

    @ViewBuilder
    var body: some View {
        header
            .onAppear(perform: loadFromAccount)
            .onChange(of: accountID) { _ in loadFromAccount() }

        if let account {
            accountContent(account)
        }
    }

    @ViewBuilder
    private func accountContent(_ account: ProviderAccount) -> some View {
        sectionHeader("账号", systemImage: "person.text.rectangle", statusColor: accountHeaderStatusColor(account))
        sectionVStack {
            accountDetails(account)
            queryModeSection(account)
            linksSection(account)
        }

        sectionDivider()

        sectionHeader("连接", systemImage: "link", statusColor: connectionHeaderStatusColor(account))
        sectionVStack {
            dashboardSection(account)
            apiKeySection(account)
        }

        sectionDivider()

        sectionHeader("路由", systemImage: "arrow.triangle.2.circlepath.circle", statusColor: routerManager.status.statusColor)
        RouterSettingsView(
            accountID: accountID,
            accountManager: accountManager,
            routerManager: routerManager,
            pendingScrollToAPIKey: $pendingScrollToAPIKey
        )
    }

    private var header: some View {
        navHeader(
            icon: "gearshape.fill",
            tint: .blue,
            title: "FreeModel 设置",
            subtitle: headerSubtitle,
            dotColor: routerManager.status.statusColor
        )
    }

    private var headerSubtitle: String {
        let count = accountManager.accounts.count
        return count == 0 ? "无账号" : "\(count) 个账号"
    }

    private func accountDetails(_ account: ProviderAccount) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("账号信息", systemImage: "person.text.rectangle")
                .font(.headline)

            HStack {
                TextField("账号名称", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .onSubmit {
                        if commitRename(input: renameText, accountID: account.id) {
                            initialDisplayName = trimmedRenameText
                        }
                    }
                Button("重命名") {
                    if commitRename(input: renameText, accountID: account.id) {
                        initialDisplayName = trimmedRenameText
                    }
                }
                .disabled(trimmedRenameText.isEmpty)
                if trimmedRenameText != initialDisplayName
                    && !trimmedRenameText.isEmpty {
                    HStack(spacing: Spacing.tight) {
                        Image(systemName: "circle.dashed")
                            .foregroundStyle(.orange)
                        Text("未保存")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    .help("尚未保存，点「重命名」或按回车提交")
                }
            }
            HStack(spacing: Spacing.standard) {
                tag("平台: \(account.displayProviderName)", systemImage: "server.rack")
                tag(account.hasDashboardSession ? "控制台已登录" : "控制台未登录", systemImage: account.hasDashboardSession ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                if account.hasAPIKey {
                    tag("已保存 API Key", systemImage: "key.fill")
                }
            }
        }
        .sectionPanel()
    }

    private func dashboardSection(_ account: ProviderAccount) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("控制台登录", systemImage: "person.crop.circle.badge.checkmark")
                .font(.headline)

            Text("每个账号会单独保存 FreeModel 控制台登录态；切换账号后刷新只使用该账号的 cookies。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: Spacing.relaxed) {
                Button("登录当前账号") {
                    FreeModelWebLoginWindowController.shared.openLogin(
                        balanceManager: balanceManager,
                        accountManager: accountManager
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .uniformButtonHeight()

                Button("刷新余额") {
                    Task { await balanceManager.fetchBalance() }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .uniformButtonHeight()
                .disabled(balanceManager.isLoading)

                Button(role: .destructive) {
                    accountManager.clearCookies(for: account.id)
                    accountManager.clearBalance(for: account.id)
                    balanceManager.syncFromActiveAccount()
                } label: {
                    Text("清除登录态")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .uniformButtonHeight()
                .tint(.red)
            }

            if let balance = account.lastBalance {
                VStack(alignment: .leading, spacing: Spacing.tight) {
                    HStack {
                        if balance.isLow {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .help("剩余额度不足 5.0")
                        }
                        Text("上次余额")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(balance.remainingFormatted)
                            .fontWeight(.semibold)
                            .foregroundStyle(balance.isLow ? .orange : .green)
                    }
                    Text("已用 \(balance.usedFormatted) / 总额 \(balance.totalFormatted) (\(String(format: "%.0f", balance.usagePercentage))%)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
        .sectionPanel()
    }

    private func apiKeySection(_ account: ProviderAccount) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("API Key", systemImage: "key.fill")
                .id("apiKeyAnchor")
                .font(.headline)

            Text("API Key 按账号单独保存，可用于当前账号的余额查询和本地 Responses 路由代理。测试连接成功后会自动保存。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: Spacing.standard) {
                VStack(alignment: .leading, spacing: Spacing.tight) {
                    if showAPIKey {
                        TextField("sk-...", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.app(.editorBody))
                            .onChange(of: apiKeyInput) { _ in
                                apiKeyStatus.markUnsavedIfPersisted()
                            }
                    } else {
                        SecureField("sk-...", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.app(.editorBody))
                            .onChange(of: apiKeyInput) { _ in
                                apiKeyStatus.markUnsavedIfPersisted()
                            }
                    }
                    apiKeyStatusBadge
                }

                VStack(alignment: .leading, spacing: Spacing.tight) {
                    HStack(spacing: 6) {
                        Button(action: { showAPIKey.toggle() }) {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .frame(width: 16, height: 16)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.regular)
                        .frame(width: 28, height: 28)
                        .disabled(isTesting)
                        .help(showAPIKey ? "隐藏 API Key" : "显示 API Key")

                        if isTesting {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 28, height: 28)
                                .help("正在测试连接")
                        }
                    }
                    Color.clear.frame(height: 22)
                }
            }

            HStack(spacing: Spacing.relaxed) {
                Button("保存") {
                    balanceManager.apiKey = apiKeyInput
                    apiKeyStatus = .saved
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .uniformButtonHeight()
                .disabled(apiKeyInput.isEmpty)

                Button("测试连接") {
                    testConnection()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .uniformButtonHeight()
                .disabled(apiKeyInput.isEmpty || isTesting)

                Button(role: .destructive) {
                    balanceManager.apiKey = nil
                    apiKeyInput = ""
                    apiKeyStatus = .empty
                } label: {
                    Text("清除 API Key")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .tint(.red)
                .uniformButtonHeight()
            }
        }
        .sectionPanel()
    }

    private func linksSection(_ account: ProviderAccount) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("快捷链接", systemImage: "link")
                .font(.headline)

            HStack(spacing: Spacing.relaxed) {
                Button("打开 \(account.displayProviderName) 控制面板") {
                    openURL(account.dashboardURL)
                }
                .buttonStyle(.bordered)

                Button("API 文档") {
                    openURL(account.docURLString)
                }
                .buttonStyle(.bordered)
            }
        }
        .sectionPanel()
    }

    private func queryModeSection(_ account: ProviderAccount) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("查询额度方式", systemImage: "magnifyingglass.circle.fill")
                .font(.headline)

            Picker("查询模式", selection: Binding(
                get: { account.queryMode },
                set: { newValue in
                    withAnimation(.easeInOut(duration: 0.18)) {
                        accountManager.updateQueryMode(newValue, for: account.id)
                    }
                }
            )) {
                ForEach(QueryMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            ZStack(alignment: .topLeading) {
                if account.queryMode == .dashboard {
                    Text("网页控制台模式：通过内置网页登录 FreeModel 并截获其会话 Cookie 刷新余额。这是最推荐、最稳定的方式。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                } else {
                    Text("API Key 模式：直接请求 OpenAI 兼容的余额接口进行额度获取。支持自定义 API Base URL。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: account.queryMode)
        }
        .sectionPanel()
    }

    private func testConnection() {
        isTesting = true
        apiKeyStatus = .testing

        let key = apiKeyInput

        Task {
            let result = await balanceManager.validateAPIKey(key)

            await MainActor.run {
                isTesting = false

                switch result {
                case .success:
                    balanceManager.apiKey = key
                    apiKeyStatus = .verified
                case .failure(.invalidAPIKey):
                    apiKeyStatus = .failed("API Key 无效")
                case .failure(.serverError(let code, let message)):
                    if code == 402 {
                        apiKeyStatus = .failed("API Key 可识别，但账户需要验证或充值")
                    } else if code == 429 {
                        apiKeyStatus = .failed("请求过于频繁")
                    } else {
                        apiKeyStatus = .failed("服务器返回错误 (\(code)): \(message)")
                    }
                case .failure(let error):
                    apiKeyStatus = .failed(error.errorDescription ?? "连接失败")
                }
            }
        }
    }

    private func loadFromAccount() {
        renameText = account?.displayName ?? ""
        initialDisplayName = account?.displayName ?? ""
        apiKeyInput = account?.apiKey ?? ""
        apiKeyStatus = .unsaved
    }

    private func tag(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .padding(.horizontal, Spacing.standard)
            .padding(.vertical, Spacing.tight)
            .background(Capsule().fill(Color.overlayFill))
    }

    private func sectionHeader(_ title: String, systemImage: String, statusColor: Color? = nil) -> some View {
        HStack(spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Spacer()
            if let color = statusColor {
                statusDot(color: color, size: 8, help: headerDotHelp(for: title))
            }
        }
        .padding(.top, Spacing.tight)
    }

    private func headerDotHelp(for title: String) -> String {
        switch title {
        case "账号": return "账号信息已配置"
        case "连接": return "控制台已登录且 API Key 已配置"
        case "路由": return routerManager.status.subtitle
        default: return ""
        }
    }

    private func accountHeaderStatusColor(_ account: ProviderAccount) -> Color? {
        return .green
    }

    private func connectionHeaderStatusColor(_ account: ProviderAccount) -> Color? {
        if account.hasDashboardSession || account.hasAPIKey { return .green }
        return .red
    }

    private func openURL(_ string: String) {
        if let url = URL(string: string) {
            NSWorkspace.shared.open(url)
        }
    }

    private func commitRename(input: String, accountID: UUID) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        accountManager.renameAccount(id: accountID, displayName: trimmed)
        return true
    }

    @ViewBuilder
    private var apiKeyStatusBadge: some View {
        let pair: (icon: String, color: Color, text: String)? = {
            switch apiKeyStatus {
            case .empty: return nil
            case .unsaved: return ("circle.dashed", .orange, "未保存")
            case .testing: return nil
            case .verified: return ("checkmark.seal.fill", .green, "已验证")
            case .failed(let msg): return ("xmark.octagon.fill", .red, msg)
            case .saved: return ("checkmark.circle.fill", .blue, "已保存")
            }
        }()
        if let pair {
            StatusBadge(icon: pair.icon, text: pair.text, tint: pair.color)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: apiKeyStatus)
        }
    }
}
