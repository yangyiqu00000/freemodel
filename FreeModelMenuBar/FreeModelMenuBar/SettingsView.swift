//
//  SettingsView.swift
//  FreeModelMenuBar
//
//  设置界面 - 多账号管理、控制台登录和 API Key 配置
//

import SwiftUI

struct SettingsView: View {
    private static let windowSize = CGSize(width: 720, height: 620)

    @EnvironmentObject var accountManager: AccountManager
    @EnvironmentObject var balanceManager: BalanceManager
    @EnvironmentObject var routerManager: RouterManager
    @StateObject private var codexInjectionLayer: AppLayer = AppLayer.shared

    enum SidebarItem: Hashable {
        case account(UUID)
        case logs
        case codexInjectionConfig(String)
    }

    @State private var selectedItem: SidebarItem? = nil
    @State private var apiKeyInput: String = ""
    @State private var showAPIKey: Bool = false
    @State private var isTesting: Bool = false

    private enum ApiKeyStatus: Equatable {
        case empty
        case unsaved
        case testing
        case verified
        case failed(String)
        case saved
    }
    @State private var apiKeyStatus: ApiKeyStatus = .empty

    @State private var renameText: String = ""
    @State private var initialDisplayName: String = ""

    @State private var pendingScrollToAPIKey: Bool = false
    @State private var pendingDeleteCodexConfig: InjectionConfiguration?
    @State private var accountCreatedToast: String? = nil
    @State private var codexConfigCreatedToast: String? = nil
    @State private var toastTask: Task<Void, Never>?

    // Router State（已移至 RouterSettingsView 的 RouterEditingState）

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebarView(
                selectedItem: $selectedItem,
                accountManager: accountManager,
                balanceManager: balanceManager,
                routerManager: routerManager,
                codexInjectionLayer: codexInjectionLayer,
                accountToast: $accountCreatedToast,
                codexToast: $codexConfigCreatedToast,
                pendingDeleteCodexConfig: $pendingDeleteCodexConfig
            )
            .frame(width: 220)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                    // 添加成功 toast（3 处共用：账号 4 chip / Codex 官方 / Codex 第三方）
                    toastBadge(value: accountCreatedToast, icon: "person.crop.circle.badge.checkmark", tint: .green)
                    toastBadge(value: codexConfigCreatedToast, icon: "key.horizontal.fill", tint: .blue)
                    if let selected = selectedItem {
                        switch selected {
                        case .account(let accountID):
                            if let account = accountManager.accounts.first(where: { $0.id == accountID }) {
                                header

                                // 3 段平等逻辑：始终展开，用 Label + Divider 分段（不再折叠）
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
                                    account: account,
                                    accountManager: accountManager,
                                    routerManager: routerManager,
                                    pendingScrollToAPIKey: $pendingScrollToAPIKey
                                )
                            } else {
                                emptyStateView(.accountGone)
                            }
                        case .logs:
                            LogsConsoleView(
                                routerManager: routerManager,
                                accountManager: accountManager
                            )
                        case .codexInjectionConfig(let cfgID):
                            CodexInjectionSettingsView(
                                appLayer: codexInjectionLayer,
                                configurationID: cfgID,
                                pendingDeleteCodexConfig: $pendingDeleteCodexConfig
                            )
                        }
                    } else {
                        emptyStateView(.noSelection)
                    }
                }
                .padding(24)
            }
            .onChange(of: pendingScrollToAPIKey) { newValue in
                if newValue {
                    withAnimation { proxy.scrollTo("apiKeyAnchor", anchor: .top) }
                    pendingScrollToAPIKey = false
                }
            }
        }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .onAppear {
            if let activeID = accountManager.activeAccountID {
                selectedItem = .account(activeID)
            } else if !accountManager.accounts.isEmpty {
                selectedItem = .account(accountManager.accounts[0].id)
            } else {
                selectedItem = .logs
            }
            loadFieldsFromActiveAccount()
        }
        .onChange(of: accountManager.activeAccountID) { newID in
            if let newID = newID {
                selectedItem = .account(newID)
            } else {
                if let firstAcc = accountManager.accounts.first {
                    selectedItem = .account(firstAcc.id)
                    accountManager.selectAccount(id: firstAcc.id)
                } else {
                    selectedItem = .logs
                }
            }
            apiKeyStatus = .unsaved
            balanceManager.syncFromActiveAccount()
            loadFieldsFromActiveAccount()
        }
    }

    // MARK: - 侧边栏已提取至 SettingsSidebarView.swift

    private func loadFieldsFromActiveAccount() {
	        guard let account = accountManager.activeAccount else {
	            renameText = ""
	            apiKeyInput = ""
	            return
	        }

	        renameText = account.displayName
	        initialDisplayName = account.displayName
	        apiKeyInput = account.apiKey ?? ""
	        apiKeyStatus = .unsaved
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
        let accountCount = accountManager.accounts.count
        let codexCount = codexInjectionLayer.injectionConfigurations.count
        let activeCodexLabel: String? = codexInjectionLayer.activeInjection.flatMap { info in
            codexInjectionLayer.injectionConfigurations.first(where: { $0.id == info.configurationID })?.label
        }
        let accountPart = accountCount == 0 ? "无账号" : "\(accountCount) 个账号"
        let codexPart: String
        if let label = activeCodexLabel {
            codexPart = "注入：\(label)"
        } else if codexCount == 0 {
            codexPart = "无注入"
        } else {
            codexPart = "\(codexCount) 条注入"
        }
        return "\(accountPart) · \(codexPart)"
    }

    /// 详情区空态（2 处共用，文案独立）
    /// - .noSelection：未选中任何项
    /// - .accountGone：选中账号刚被删（不再误导为"还没有账号"）
    enum EmptyStateKind {
        case noSelection
        case accountGone
    }

    private func emptyStateView(_ kind: EmptyStateKind) -> some View {
        VStack(spacing: 12) {
            switch kind {
            case .noSelection:
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
                Text("还没有选中账号")
                    .font(.headline)
                Text("点击侧边栏右上角的 + 添加账号，或选中现有账号")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case .accountGone:
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("该账号已不存在")
                    .font(.headline)
                Text("可能刚被删除，刷新或选中其他账号")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .padding(24)
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
                            initialDisplayName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                Button("重命名") {
                    if commitRename(input: renameText, accountID: account.id) {
                        initialDisplayName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if renameText.trimmingCharacters(in: .whitespacesAndNewlines) != initialDisplayName
                    && !renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "circle.dashed")
                            .foregroundStyle(.orange)
                        Text("未保存")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    .help("尚未保存，点「重命名」或按回车提交")
                }
            }
	            HStack(spacing: 8) {
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

            HStack(spacing: 12) {
                Button("登录当前账号") {
                    FreeModelWebLoginWindowController.shared.openLogin(
                        balanceManager: balanceManager,
                        accountManager: accountManager
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .frame(height: 28)

                Button("刷新余额") {
                    Task { await balanceManager.fetchBalance() }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .frame(height: 28)
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
                .frame(height: 28)
                .tint(.red)
            }

            if let balance = account.lastBalance {
                VStack(alignment: .leading, spacing: 4) {
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

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    // 输入框（独立，无 overlay）
                    if showAPIKey {
                        TextField("sk-...", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .onChange(of: apiKeyInput) { _ in
                                if case .verified = apiKeyStatus { apiKeyStatus = .unsaved }
                                if case .saved = apiKeyStatus { apiKeyStatus = .unsaved }
                            }
                    } else {
                        SecureField("sk-...", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .onChange(of: apiKeyInput) { _ in
                                if case .verified = apiKeyStatus { apiKeyStatus = .unsaved }
                                if case .saved = apiKeyStatus { apiKeyStatus = .unsaved }
                            }
                    }
                    // 状态徽章：移出 overlay，改为输入框下方独立一行（视觉层级清晰）
                    apiKeyStatusBadge
                }

                // 眼睛按钮 + 测试进度圈 — 控制 28pt 高与下方按钮行对齐
                VStack(alignment: .leading, spacing: 4) {
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
                    // 占位，与左侧 apiKeyStatusBadge 对齐（保持两列顶部对齐）
                    Color.clear.frame(height: 22)
                }
            }

            HStack(spacing: 12) {
                Button("保存") {
                    balanceManager.apiKey = apiKeyInput
                    apiKeyStatus = .saved
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .frame(height: 28)
                .disabled(apiKeyInput.isEmpty)

                Button("测试连接") {
                    testConnection()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .frame(height: 28)
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
                .frame(height: 28)
            }


        }
        .sectionPanel()
    }

    private func linksSection(_ account: ProviderAccount) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("快捷链接", systemImage: "link")
                .font(.headline)

            HStack(spacing: 12) {
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

// customURLsSection / providerPreset / routerSection / saveRouterSettings 已移至 RouterSettingsView.swift

	    private func tag(_ text: String, systemImage: String) -> some View {
	        Label(text, systemImage: systemImage)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
	            .background(Capsule().fill(Color.overlayFill))
	    }

    // MARK: - Toast 自动隐藏（Task 取消模式防过期复活）

    private func showToast<T: Equatable>(_ value: T?, at binding: Binding<T?>, seconds: Double = 3.0) {
        toastTask?.cancel()
        withAnimation { binding.wrappedValue = value }
        guard value != nil else { return }
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            withAnimation { binding.wrappedValue = nil }
        }
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
        .padding(.top, 4)
    }

    // MARK: - 详情区 header status dot help（按段标题返回对应解释）

    private func headerDotHelp(for title: String) -> String {
        switch title {
        case "账号": return "账号信息已配置"
        case "连接": return "控制台已登录且 API Key 已配置"
        case "路由": return routerManager.status.subtitle
        default: return ""
        }
    }

    // MARK: - 详情区 3 段 header status dot 计算（账号 / 连接 / 路由 子段健康度摘要）

    private func accountHeaderStatusColor(_ account: ProviderAccount) -> Color? {
        // 账号段：只要存在即绿（无有效语义"未配置账号"——账号就是当前选中）
        return .green
    }

    private func connectionHeaderStatusColor(_ account: ProviderAccount) -> Color? {
        // 连接段：控制台已登录 或 API Key 已设 = 绿；都未设 = 红
        if account.hasDashboardSession || account.hasAPIKey { return .green }
        return .red
    }

    // MARK: - URL 打开（if let URL + NSWorkspace.open 同一来源，3 处共用）

    private func openURL(_ string: String) {
        if let url = URL(string: string) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - 重命名账号提交（trim + 非空 + renameAccount 同一来源，3 处共用）

    /// 提交账号重命名：trim 后非空才调 renameAccount。返回 true 表示已提交成功（详情页用于同步 initialDisplayName）
    private func commitRename(input: String, accountID: UUID) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        accountManager.renameAccount(id: accountID, displayName: trimmed)
        return true
    }

    // MARK: - API Key 状态徽章（内嵌文本框右下角，统一 22pt 高，0.2s 淡入）

    @ViewBuilder
    private var apiKeyStatusBadge: some View {
        let pair: (icon: String, color: Color, text: String)? = {
            switch apiKeyStatus {
            case .empty: return nil
            case .unsaved: return ("circle.dashed", .orange, "未保存")
            case .testing: return nil  // testing 期间 ProgressView 已经在外侧显示
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

// sectionPanel / sectionVStack / addRowPanel 已移至 ViewExtensions.swift
