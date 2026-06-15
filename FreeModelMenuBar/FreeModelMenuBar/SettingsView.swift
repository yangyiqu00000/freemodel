//
//  SettingsView.swift
//  FreeModelMenuBar
//
//  设置界面 - 多账号管理、控制台登录和 API Key 配置
//

import SwiftUI

struct SettingsView: View {

private enum AddKind { case account, codex }
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
    @State private var selectedRefreshInterval: TimeInterval = 300
    @State private var showTestResult: Bool = false
    @State private var testResultMessage: String = ""
    @State private var testResultSuccess: Bool = false
    @State private var isTesting: Bool = false
    @State private var renameText: String = ""
    @State private var apiURLInput: String = ""
    @State private var dashboardURLInput: String = ""

    // 账号 sidebar state
    @State private var addExpanded: AddKind? = nil
    @State private var newAccountLabel: String = ""

    // Codex 注入 sidebar state
    @State private var newCodexLabel: String = ""
    @State private var newCodexProvider: String = ""

    // Router State
    @State private var routerEnabled: Bool = false
    @State private var routerPort: String = "38440"
    @State private var routerUpstreamURL: String = ""
    @State private var routerRouteModel: String = ""
    @State private var routerDefaultModel: String = ""
    @State private var routerStreaming: Bool = true
    @State private var routerFailoverEnabled: Bool = true
    @State private var routerMaxConcurrency: String = "0"
    @State private var routerMinIntervalMs: String = "0"

    private let refreshOptions: [(String, TimeInterval)] = [
        ("1 分钟", 60),
        ("5 分钟", 300),
        ("10 分钟", 600),
        ("30 分钟", 1800),
        ("1 小时", 3600)
    ]

    var body: some View {
        HStack(spacing: 0) {
            accountList
                .frame(width: 220)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let selected = selectedItem {
                        switch selected {
                        case .account(let accountID):
                            if let account = accountManager.accounts.first(where: { $0.id == accountID }) {
                                header
                                accountDetails(account)
                                queryModeSection(account)
                                dashboardSection(account)
                                apiKeySection(account)
                                routerSection(account)
                                customURLsSection(account)
                                refreshSection
                                linksSection(account)
                            } else {
                                emptyState
                            }
                        case .logs:
                            logsHeader
                            logsConsoleSection
                        case .codexInjectionConfig(let cfgID):
                            CodexInjectionSettingsView(appLayer: codexInjectionLayer, configurationID: cfgID)
                        }
                    } else {
                        emptyState
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 720, height: 620)
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
            showTestResult = false
            balanceManager.syncFromActiveAccount()
            loadFieldsFromActiveAccount()
        }
    }

    private var accountList: some View {
        VStack(alignment: .leading, spacing: 12) {

            List(selection: Binding(
                get: { selectedItem },
                set: { newItem in
                    if let newItem = newItem {
                        selectedItem = newItem
                        if case .account(let uuid) = newItem {
                            accountManager.selectAccount(id: uuid)
                            balanceManager.syncFromActiveAccount()
                        }
                    }
                }
            )) {
                Section(header: accountsSectionHeader) {
                    ForEach(accountManager.accounts) { account in
                    if addExpanded == .account {
                        accountsInlineAddRow
                    }
                        accountRow(account)
                            .tag(SidebarItem.account(account.id))
                            .contextMenu {
                                Button(role: .destructive) {
                                    _ = accountManager.deleteAccount(id: account.id)
                                    balanceManager.syncFromActiveAccount()
                                    if case .account(let id) = selectedItem, id == account.id {
                                        selectedItem = nil
                                    }
                                } label: {
                                    Label("删除账号", systemImage: "trash")
                                }
                            }
                    }
                }

                Section(header: codexSectionHeader) {
                    if addExpanded == .codex {
                        codexInlineAddRow
                    }
                        ForEach(codexInjectionLayer.injectionConfigurations) { cfg in
                            codexConfigRow(cfg)
                                .tag(SidebarItem.codexInjectionConfig(cfg.id))
                                .contextMenu {
                                    Button {
                                        codexInjectionLayer.activateConfiguration(id: cfg.id)
                                    } label: {
                                        Label("激活", systemImage: "bolt.fill")
                                    }
                                    Button(role: .destructive) {
                                        codexInjectionLayer.deleteConfiguration(id: cfg.id)
                                        if case .codexInjectionConfig(let id) = selectedItem, id == cfg.id {
                                            selectedItem = nil
                                        }
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                        }
                }

                Section(header: Text("运行日志")) {
                    HStack {
                        SidebarRow(
                            icon: "terminal.fill",
                            iconColor: routerManager.status == .running ? .green : .secondary,
                            title: "运行日志",
                            subtitle: routerStatusSubtitle,
                            statusColor: routerManager.status == .running ? .green : nil
                        )
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }


    // MARK: - 账号 section 标题（与 Codex 注入同形状：label + 右侧 +）

    private var accountsSectionHeader: some View {
        HStack {
            Label("账号", systemImage: "person.2.fill")
                .font(.headline)
            Spacer()
            Button {
                addExpanded = (addExpanded == .account) ? nil : .account
                if addExpanded == .account {
                    newAccountLabel = "新账号 \(Self.shortNow())"
                }
            } label: {
                Image(systemName: addExpanded == .account ? "minus" : "plus")
            }
            .buttonStyle(.borderless)
            .help("新增账号")
        }
    }
    // MARK: - 内联账号添加行（与 codexInlineAddRow 同形状）

    private var accountsInlineAddRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("名称").frame(width: 56, alignment: .leading).font(.caption).foregroundStyle(.secondary)
                TextField("例如：我的 DeepSeek", text: $newAccountLabel)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("种类").frame(width: 56, alignment: .leading).font(.caption).foregroundStyle(.secondary)
                Button {
                    let account = accountManager.createAccount(displayName: newAccountLabel, providerID: "freemodel")
                    accountManager.selectAccount(id: account.id)
                    balanceManager.syncFromActiveAccount()
                    addExpanded = nil
                } label: {
                    Label("FreeModel 网页", systemImage: "globe")
                }
                Button {
                    let account = accountManager.createAccount(displayName: newAccountLabel, providerID: "deepseek")
                    accountManager.selectAccount(id: account.id)
                    balanceManager.syncFromActiveAccount()
                    addExpanded = nil
                } label: {
                    Label("DeepSeek API", systemImage: "key.fill")
                }
                Button {
                    let account = accountManager.createAccount(displayName: newAccountLabel, providerID: "openrouter")
                    accountManager.selectAccount(id: account.id)
                    balanceManager.syncFromActiveAccount()
                    addExpanded = nil
                } label: {
                    Label("OpenRouter API", systemImage: "arrow.triangle.branch")
                }
                Button {
                    let account = accountManager.createAccount(displayName: newAccountLabel, providerID: "modelscope")
                    accountManager.selectAccount(id: account.id)
                    balanceManager.syncFromActiveAccount()
                    addExpanded = nil
                } label: {
                    Label("ModelScope API", systemImage: "cube")
                }
                Spacer()
                Button("取消") {
                    addExpanded = nil
                }
            }
            .font(.caption)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.blue.opacity(0.08))
        )
    }

    private var codexSectionHeader: some View {
        HStack {
            Label("Codex 注入", systemImage: "key.horizontal")
                .font(.headline)
            Spacer()
            Button {
                addExpanded = (addExpanded == .codex) ? nil : .codex
                if addExpanded == .codex {
                    newCodexLabel = "新配置 \(Self.shortNow())"
                    newCodexProvider = "custom-\(Self.shortNow())"
                }
            } label: {
                Image(systemName: addExpanded == .codex ? "minus" : "plus")
            }
            .buttonStyle(.borderless)
            .help("添加一条新的注入配置")
        }
    }
    // MARK: - 内联添加行（替代 sheet）

    private var codexInlineAddRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("标签").frame(width: 56, alignment: .leading).font(.caption).foregroundStyle(.secondary)
                TextField("例如：本地 relay", text: $newCodexLabel)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("Provider").frame(width: 56, alignment: .leading).font(.caption).foregroundStyle(.secondary)
                TextField("例如：local-relay", text: $newCodexProvider)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("种类").frame(width: 56, alignment: .leading).font(.caption).foregroundStyle(.secondary)
                Button {
                    codexInjectionLayer.prepareOfficialLoginSession(label: newCodexLabel)
                    addExpanded = nil
                } label: {
                    Label("官方", systemImage: "person.crop.circle.badge.checkmark")
                }
                Button {
                    codexInjectionLayer.addEmptyThirdPartyConfiguration(label: newCodexLabel, providerID: newCodexProvider)
                    addExpanded = nil
                } label: {
                    Label("第三方", systemImage: "square.and.pencil")
                }
                Spacer()
                Button("取消") {
                    addExpanded = nil
                }
            }
            .font(.caption)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.blue.opacity(0.08))
        )
    }

    // MARK: - 侧边栏统一行组件（账号行 / 注入配置行 / 日志行 共用）

    private struct SidebarRow: View {
        let icon: String
        let iconColor: Color
        let title: String
        let subtitle: String?
        let statusColor: Color?
        let subtitleColor: Color

        init(icon: String,
             iconColor: Color = .secondary,
             title: String,
             subtitle: String? = nil,
             statusColor: Color? = nil,
             subtitleColor: Color = .secondary) {
            self.icon = icon
            self.iconColor = iconColor
            self.title = title
            self.subtitle = subtitle
            self.statusColor = statusColor
            self.subtitleColor = subtitleColor
        }

        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(iconColor)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(subtitleColor)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if let statusColor {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.vertical, 3)
        }
    }
    // MARK: - 单条注入配置行

    private func codexConfigRow(_ cfg: InjectionConfiguration) -> some View {
        let isActive = (codexInjectionLayer.activeInjection?.configurationID == cfg.id)
        return SidebarRow(
            icon: isActive ? "checkmark.circle.fill" : "circle",
            iconColor: isActive ? .green : .secondary,
            title: cfg.label,
            subtitle: "\(cfg.kind == .official ? "官方" : "第三方") · \(cfg.providerID)",
            statusColor: isActive ? .green : nil
        )
    }

    private static func shortNow() -> String {
        let f = DateFormatter()
        f.dateFormat = "MMdd-HHmm"
        return f.string(from: Date())
    }

	    private func loadFieldsFromActiveAccount() {
	        guard let account = accountManager.activeAccount else {
	            renameText = ""
	            apiURLInput = ""
	            dashboardURLInput = ""
	            apiKeyInput = ""
	            selectedRefreshInterval = 300
	            return
	        }

	        selectedRefreshInterval = account.refreshInterval
	        renameText = account.displayName
	        apiURLInput = account.apiBaseURL
	        dashboardURLInput = account.dashboardURL
	        apiKeyInput = account.apiKey ?? ""

	        let s = account.activeRouterSettings
        routerEnabled = s.enabled
        routerPort = String(s.port)
        routerUpstreamURL = s.upstreamBaseURL
        routerRouteModel = s.routeModel
        routerDefaultModel = s.defaultModel
        routerStreaming = s.supportsStreaming
        routerFailoverEnabled = s.isFailoverEnabled
        routerMaxConcurrency = String(s.maxConcurrency ?? 0)
        routerMinIntervalMs = String(s.minIntervalMs ?? 0)
	    }

    private func accountRow(_ account: ProviderAccount) -> some View {
        SidebarRow(
            icon: account.hasDashboardSession ? "checkmark.circle.fill" : "person.crop.circle",
            iconColor: account.hasDashboardSession ? .green : .secondary,
            title: account.displayName,
            subtitle: accountStatusText(account)
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "gearshape.fill")
                .font(.title2)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text("FreeModel 设置")
                    .font(.title2)
                    .fontWeight(.bold)
                HStack(spacing: 6) {
                    Text(headerSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let dot = headerStatusDot {
                        Circle()
                            .fill(dot)
                            .frame(width: 6, height: 6)
                    }
                }
            }
            Spacer()
        }
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

    private var headerStatusDot: Color? {
        switch routerManager.status {
        case .running: return .green
        case .starting: return .orange
        case .failed, .portInUse, .missingKey: return .red
        case .off: return nil
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 42))
                .foregroundStyle(.orange)
            Text("还没有账号")
                .font(.headline)
            Text("点击侧边栏右上角的 + 添加账号")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
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
                        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        accountManager.renameAccount(id: account.id, displayName: trimmed)
                    }
                Button("重命名") {
                    let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    accountManager.renameAccount(id: account.id, displayName: trimmed)
                }
                .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
	            HStack(spacing: 8) {
	                let platformName = providerName(account)
	                tag("平台: \(platformName)", systemImage: "server.rack")
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

                Button("刷新余额") {
                    Task { await balanceManager.fetchBalance() }
                }
                .buttonStyle(.bordered)
                .disabled(balanceManager.isLoading)

                Button("清除登录态") {
                    accountManager.clearCookies(for: account.id)
                    accountManager.clearBalance(for: account.id)
                    balanceManager.syncFromActiveAccount()
                }
                .buttonStyle(.bordered)
            }

            if let balance = account.lastBalance {
                HStack {
                    Text("上次余额")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(balance.remainingFormatted)
                        .fontWeight(.semibold)
                        .foregroundStyle(balance.isLow ? .orange : .green)
                }
                .font(.caption)
            }
        }
        .sectionPanel()
    }

    private func apiKeySection(_ account: ProviderAccount) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("API Key", systemImage: "key.fill")
                .font(.headline)

	            Text("API Key 按账号单独保存，可用于当前账号的余额查询和本地 Responses 路由代理。测试连接成功后会自动保存。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                if showAPIKey {
                    TextField("sk-...", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                } else {
                    SecureField("sk-...", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                Button(action: { showAPIKey.toggle() }) {
                    Image(systemName: showAPIKey ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
            }

            HStack(spacing: 12) {
                Button("保存") {
                    balanceManager.apiKey = apiKeyInput
                    showTestResult = true
                    testResultSuccess = true
                    testResultMessage = "已保存到当前账号"
                }
                .buttonStyle(.borderedProminent)
                .disabled(apiKeyInput.isEmpty)

                Button("测试连接") {
                    testConnection()
                }
                .buttonStyle(.bordered)
                .disabled(apiKeyInput.isEmpty || isTesting)

                Button("清除 API Key") {
                    balanceManager.apiKey = nil
                    apiKeyInput = ""
                    showTestResult = true
                    testResultSuccess = true
                    testResultMessage = "已清除当前账号的 API Key"
                }
                .buttonStyle(.bordered)
            }

            if isTesting {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("正在测试连接...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if showTestResult {
                HStack(spacing: 6) {
                    Image(systemName: testResultSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(testResultSuccess ? .green : .red)
                    Text(testResultMessage)
                        .font(.caption)
                        .foregroundStyle(testResultSuccess ? .green : .red)
                }
            }
        }
        .sectionPanel()
    }

    private var refreshSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("自动刷新频率", systemImage: "clock.fill")
                .font(.headline)

            Picker("刷新频率", selection: $selectedRefreshInterval) {
                ForEach(refreshOptions, id: \.1) { label, interval in
                    Text(label).tag(interval)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedRefreshInterval) { newValue in
                if let activeAccount = accountManager.activeAccount {
                    accountManager.updateRefreshInterval(newValue, for: activeAccount.id)
                }
                balanceManager.updateRefreshInterval(newValue)
            }
        }
        .sectionPanel()
    }

    private func linksSection(_ account: ProviderAccount) -> some View {
        let providerName: String
        let docURLString: String
        
        switch account.providerID.lowercased() {
        case "deepseek":
            providerName = "DeepSeek"
            docURLString = "https://api-docs.deepseek.com"
        case "openrouter":
            providerName = "OpenRouter"
            docURLString = "https://openrouter.ai/docs"
        case "modelscope":
            providerName = "ModelScope"
            docURLString = "https://modelscope.cn/docs/model-service/API-Inference/api-provider"
        default:
            providerName = "FreeModel"
            docURLString = "\(account.dashboardURL)/docs"
        }

        return VStack(alignment: .leading, spacing: 10) {
            Label("快捷链接", systemImage: "link")
                .font(.headline)

            HStack(spacing: 12) {
                Button("打开 \(providerName) 控制面板") {
                    if let url = URL(string: account.dashboardURL) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)

                Button("API 文档") {
                    if let url = URL(string: docURLString) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .sectionPanel()
    }

    private func testConnection() {
        isTesting = true
        showTestResult = false

        let key = apiKeyInput

        Task {
            let result = await balanceManager.validateAPIKey(key)

            await MainActor.run {
                isTesting = false
                showTestResult = true

                switch result {
                case .success:
	                    balanceManager.apiKey = key
	                    testResultMessage = "连接成功，已保存到当前账号"
	                    testResultSuccess = true
                case .failure(.invalidAPIKey):
                    testResultMessage = "API Key 无效"
                    testResultSuccess = false
                case .failure(.serverError(let code, let message)):
                    if code == 402 {
                        testResultMessage = "API Key 可识别，但账户需要验证或充值"
                    } else if code == 429 {
                        testResultMessage = "请求过于频繁"
                    } else {
                        testResultMessage = "服务器返回错误 (\(code)): \(message)"
                    }
                    testResultSuccess = false
                case .failure(let error):
                    testResultMessage = error.errorDescription ?? "连接失败"
                    testResultSuccess = false
                }
            }
        }
    }

    private func deleteActiveAccount() {
        guard let account = accountManager.activeAccount else { return }
        _ = accountManager.deleteAccount(id: account.id)
        apiKeyInput = ""
        balanceManager.syncFromActiveAccount()
    }

    private func accountStatusText(_ account: ProviderAccount) -> String {
        let status: String
        switch account.queryMode {
        case .dashboard:
            status = account.hasDashboardSession ? "已登录" : "未登录"
        case .apiKey:
            status = account.hasAPIKey ? "已设 Key" : "未设 Key"
        }
        
        if let balance = account.lastBalance {
            return "\(balance.remainingFormatted) · \(status)"
        }
        return account.queryMode == .dashboard ? "\(status)控制台" : status
    }

    private func queryModeSection(_ account: ProviderAccount) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("查询额度方式", systemImage: "magnifyingglass.circle.fill")
                .font(.headline)
            
            Picker("查询模式", selection: Binding(
                get: { account.queryMode },
                set: { newValue in
                    accountManager.updateQueryMode(newValue, for: account.id)
                }
            )) {
                ForEach(QueryMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            
            if account.queryMode == .dashboard {
                Text("网页控制台模式：通过内置网页登录 FreeModel 并截获其会话 Cookie 刷新余额。这是最推荐、最稳定的方式。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("API Key 模式：直接请求 OpenAI 兼容的余额接口进行额度获取。支持自定义 API Base URL。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sectionPanel()
    }

    private func customURLsSection(_ account: ProviderAccount) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("自定义服务器地址", systemImage: "network")
                .font(.headline)

            HStack(spacing: 8) {
                Text("常用预设:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
	                Button("FreeModel") {
	                    apiURLInput = "https://api.freemodel.dev"
	                    dashboardURLInput = "https://freemodel.dev"
	                    accountManager.updateURLs(apiURL: apiURLInput, dashboardURL: dashboardURLInput, for: account.id)
	                    accountManager.updateQueryMode(.dashboard, for: account.id)
	                    applyRouterPreset(for: account.id, upstreamURL: "https://api.freemodel.dev/v1", defaultModel: "codex-mini")
	                    loadFieldsFromActiveAccount()
	                    showTestResult = true
	                    testResultSuccess = true
	                    testResultMessage = "已切换为 FreeModel 预设地址"
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
	                Button("DeepSeek") {
	                    apiURLInput = "https://api.deepseek.com"
	                    dashboardURLInput = "https://platform.deepseek.com"
	                    accountManager.updateURLs(apiURL: apiURLInput, dashboardURL: dashboardURLInput, for: account.id)
	                    accountManager.updateQueryMode(.apiKey, for: account.id)
	                    applyRouterPreset(for: account.id, upstreamURL: "https://api.deepseek.com/v1", defaultModel: "deepseek-chat")
	                    loadFieldsFromActiveAccount()
	                    showTestResult = true
	                    testResultSuccess = true
	                    testResultMessage = "已切换为 DeepSeek 预设地址"
                }
                .buttonStyle(.bordered)
                .controlSize(.small)


                Button("OpenRouter") {
                    apiURLInput = "https://openrouter.ai/api/v1"
                    dashboardURLInput = "https://openrouter.ai"
                    accountManager.updateURLs(apiURL: apiURLInput, dashboardURL: dashboardURLInput, for: account.id)
                    accountManager.updateQueryMode(.apiKey, for: account.id)
                    applyRouterPreset(for: account.id, upstreamURL: "https://openrouter.ai/api/v1", defaultModel: "deepseek/deepseek-v4-flash:free")
                    loadFieldsFromActiveAccount()
                    showTestResult = true
                    testResultSuccess = true
                    testResultMessage = "已切换为 OpenRouter 预设地址"
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("ModelScope") {
                    apiURLInput = "https://api-inference.modelscope.cn"
                    dashboardURLInput = "https://modelscope.cn"
                    accountManager.updateURLs(apiURL: apiURLInput, dashboardURL: dashboardURLInput, for: account.id)
                    accountManager.updateQueryMode(.apiKey, for: account.id)
                    applyRouterPreset(for: account.id, upstreamURL: "https://api-inference.modelscope.cn/v1", defaultModel: "ZhipuAI/GLM-5.1")
                    loadFieldsFromActiveAccount()
                    showTestResult = true
                    testResultSuccess = true
                    testResultMessage = "已切换为 ModelScope 预设地址"
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text("控制台网页 Base URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("https://freemodel.dev", text: $dashboardURLInput)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("API Base URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("https://api.freemodel.dev", text: $apiURLInput)
                    .textFieldStyle(.roundedBorder)
            }

            Button("保存服务器地址") {
                accountManager.updateURLs(apiURL: apiURLInput, dashboardURL: dashboardURLInput, for: account.id)
                showTestResult = true
                testResultSuccess = true
                testResultMessage = "服务器地址已保存"
            }
            .buttonStyle(.bordered)
            .disabled(apiURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                      dashboardURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .sectionPanel()
    }

	    private func tag(_ text: String, systemImage: String) -> some View {
	        Label(text, systemImage: systemImage)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
	            .background(Capsule().fill(Color.gray.opacity(0.12)))
	    }

	    private func providerName(_ account: ProviderAccount) -> String {
	        if account.providerID == "deepseek" || account.apiBaseURL.lowercased().contains("deepseek") {
	            return "DeepSeek"
	        }
	        return "FreeModel"
	    }

    private func applyRouterPreset(for accountID: UUID, upstreamURL: String, defaultModel: String) {
        let existing = accountManager.account(id: accountID)?.activeRouterSettings ?? RouterSettings(
            enabled: false,
            port: 38440,
            upstreamBaseURL: upstreamURL,
            routeModel: "codex-mini",
            defaultModel: defaultModel,
            supportsStreaming: true,
            maxConcurrency: 0,
            minIntervalMs: 0
        )
        let settings = RouterSettings(
            enabled: existing.enabled,
            port: existing.port,
            upstreamBaseURL: upstreamURL,
            routeModel: existing.routeModel.isEmpty ? "codex-mini" : existing.routeModel,
            defaultModel: defaultModel,
            supportsStreaming: true,
            maxConcurrency: existing.maxConcurrency ?? 0,
            minIntervalMs: existing.minIntervalMs ?? 0
        )
        accountManager.updateRouterSettings(settings, for: accountID)
    }

    // MARK: - Router Section

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
            .font(.caption2)
            .fontWeight(.bold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(.white)
            .background(RoundedRectangle(cornerRadius: 4).fill(color))
    }

    private func logRowView(_ log: RouterLogEntry) -> some View {
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
        .font(.system(size: 10, weight: .regular, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func saveRouterSettings() {
        guard let account = accountManager.activeAccount else { return }
        let portVal = Int(routerPort) ?? 38440
        let maxConcurrencyVal = Int(routerMaxConcurrency) ?? 0
        let minIntervalMsVal = Int(routerMinIntervalMs) ?? 0
        let newSettings = RouterSettings(
            enabled: routerEnabled,
            port: portVal,
            upstreamBaseURL: routerUpstreamURL.trimmingCharacters(in: .whitespacesAndNewlines),
            routeModel: routerRouteModel.trimmingCharacters(in: .whitespacesAndNewlines),
            defaultModel: routerDefaultModel.trimmingCharacters(in: .whitespacesAndNewlines),
            supportsStreaming: routerStreaming,
            maxConcurrency: maxConcurrencyVal,
            minIntervalMs: minIntervalMsVal,
            failoverEnabled: routerFailoverEnabled
        )
        accountManager.updateRouterSettings(newSettings, for: account.id)
        routerManager.syncStateWithActiveAccount()
    }

    private func routerSection(_ account: ProviderAccount) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("本地 Responses 路由代理", systemImage: "arrow.triangle.2.circlepath.circle")
                    .font(.headline)
                Spacer()
                statusBadge(routerManager.status)
            }

            Text("为当前账号开启本地端口代理，将输入的 Responses 协议请求（如 Codex/cc switch 客户端发来）自动中转为 Chat Completions 协议发送给上游服务商。")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Switch
            HStack {
                Toggle(isOn: Binding(
                    get: { routerEnabled },
                    set: { newValue in
                        routerEnabled = newValue
                        saveRouterSettings()
                    }
                )) {
                    Text(routerEnabled ? "正在运行代理" : "启用本地路由代理")
                        .fontWeight(.semibold)
                }
                .disabled(!account.hasAPIKey)
                
                if !account.hasAPIKey {
                    Text("(需要配置 API Key)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                
                Spacer()
                
                if routerManager.status == .running {
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        let portVal = Int(routerPort) ?? 38440
                        NSPasteboard.general.setString("http://127.0.0.1:\(portVal)/v1", forType: .string)
                    }) {
                        Label("复制 Base URL", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 4)

            if routerEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("上游预设:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
	                        Button("DeepSeek") {
	                            routerUpstreamURL = "https://api.deepseek.com/v1"
	                            routerDefaultModel = "deepseek-chat"
	                            routerRouteModel = "codex-mini"
	                            routerStreaming = true
	                            routerFailoverEnabled = true
	                            saveRouterSettings()
	                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Button("ModelScope") {
                            routerUpstreamURL = "https://api-inference.modelscope.cn/v1"
                            routerDefaultModel = "ZhipuAI/GLM-5.1"
                            routerRouteModel = "codex-mini"
                            routerStreaming = true
                            routerFailoverEnabled = true
                            saveRouterSettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)


                            Button("OpenRouter") {
                                routerUpstreamURL = "https://openrouter.ai/api/v1"
                                routerDefaultModel = "deepseek/deepseek-v4-flash:free"
                                routerRouteModel = "codex-mini"
                                routerStreaming = true
                                routerFailoverEnabled = true
                                saveRouterSettings()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("本地代理端口")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            TextField("38440", text: $routerPort)
                                .textFieldStyle(.roundedBorder)
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(routerFieldEmpty(routerPort) ? .red.opacity(0.6) : .clear, lineWidth: 1.5))
                                .frame(width: 80)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("对外暴露模型名")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            TextField("codex-mini", text: $routerRouteModel)
                                .textFieldStyle(.roundedBorder)
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(routerFieldEmpty(routerRouteModel) ? .red.opacity(0.6) : .clear, lineWidth: 1.5))
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("上游 API Base URL")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        TextField("https://api.deepseek.com/v1", text: $routerUpstreamURL)
                            .textFieldStyle(.roundedBorder)
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(routerFieldEmpty(routerUpstreamURL) ? .red.opacity(0.6) : .clear, lineWidth: 1.5))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("映射到上游模型名")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        TextField("deepseek-chat", text: $routerDefaultModel)
                            .textFieldStyle(.roundedBorder)
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(routerFieldEmpty(routerDefaultModel) ? .red.opacity(0.6) : .clear, lineWidth: 1.5))
                    }

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("最大并发数 (0为无限制)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            TextField("0", text: $routerMaxConcurrency)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("最小请求间隔 (毫秒, 0为无限制)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            TextField("0", text: $routerMinIntervalMs)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    HStack(spacing: 20) {
                        Toggle("流式响应 (Streaming)", isOn: $routerStreaming)
                            .font(.caption)
                        Toggle("自动灾备转移 (Failover)", isOn: $routerFailoverEnabled)
                            .font(.caption)
                        Spacer()
                        Button("保存及重载配置") {
                            saveRouterSettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!routerIsValid())
                    }
                    .padding(.top, 4)
                }
                .padding(.all, 10)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.05)))
            }
        }
        .sectionPanel()
    }

    // MARK: - 路由器设置校验

    private func routerFieldEmpty(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func routerIsValid() -> Bool {
        !routerFieldEmpty(routerPort)
            && !routerFieldEmpty(routerUpstreamURL)
            && !routerFieldEmpty(routerRouteModel)
            && !routerFieldEmpty(routerDefaultModel)
    }

    // MARK: - Global Logs Console Views & Actions

    private var logsHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "terminal.fill")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text("路由代理运行日志")
                    .font(.title2)
                    .fontWeight(.bold)
                HStack(spacing: 6) {
                    Text(routerStatusSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let dot = headerStatusDot {
                        Circle()
                            .fill(dot)
                            .frame(width: 6, height: 6)
                    }
                }
            }
            Spacer()
        }
    }

    private var logsConsoleSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // State summary panel
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("运行状态", systemImage: "info.circle.fill")
                        .font(.headline)
                    Spacer()
                    statusBadge(routerManager.status)
                }

                if let activeAccount = accountManager.activeAccount {
                    let settings = activeAccount.activeRouterSettings
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("活动账号:")
                                .foregroundStyle(.secondary)
                            Text(activeAccount.displayName)
                                .fontWeight(.semibold)
                        }
                        if settings.enabled && routerManager.status == .running {
                            HStack {
                                Text("本地监听:")
                                    .foregroundStyle(.secondary)
                                Text("http://127.0.0.1:\(settings.port)/v1")
                                    .font(.system(.caption, design: .monospaced))
                            }
                            HStack {
                                Text("上游接口:")
                                    .foregroundStyle(.secondary)
                                Text(settings.upstreamBaseURL)
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }
                    }
                    .font(.caption)
                } else {
                    Text("请先添加并激活一个账号以配置和启动路由。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    if routerManager.status == .running, let activeAccount = accountManager.activeAccount {
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            let portVal = activeAccount.activeRouterSettings.port
                            NSPasteboard.general.setString("http://127.0.0.1:\(portVal)/v1", forType: .string)
                        }) {
                            Label("复制 Base URL", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(action: copyAllLogs) {
                        Label("复制所有日志", systemImage: "doc.on.doc.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(routerManager.logs.isEmpty)

                    Button(action: {
                        routerManager.logs.removeAll()
                    }) {
                        Label("清除日志", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .disabled(routerManager.logs.isEmpty)
                }
                .padding(.top, 4)
            }
            .sectionPanel()

            // Console terminal container
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
                                logRowView(log)
                                    .contextMenu {
                                        Button("复制此行") {
                                            copySingleLog(log)
                                        }
                                        if let err = log.error, !err.isEmpty {
                                            Button("复制错误详情") {
                                                NSPasteboard.general.clearContents()
                                                NSPasteboard.general.setString(err, forType: .string)
                                            }
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
                .textSelection(.enabled) // Enable native text selection
            }
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
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(allLogs, forType: .string)
    }

    // MARK: - 路由状态文本（侧边栏日志行 + 详情区 header 共用）

    private var routerStatusSubtitle: String {
        switch routerManager.status {
        case .off: return "路由未启动"
        case .starting: return "路由启动中…"
        case .running: return "路由运行中"
        case .failed: return "路由启动失败"
        case .portInUse: return "端口被占用"
        case .missingKey: return "缺少 API Key"
        }
    }
}

private extension View {
    func sectionPanel() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1)))
    }
}
