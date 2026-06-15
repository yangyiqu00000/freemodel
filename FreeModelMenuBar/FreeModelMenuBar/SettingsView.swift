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
    @State private var isTesting: Bool = false

    // API Key 状态机（6 种状态，原 3 个 bool 收敛为 1 个枚举）
    private enum ApiKeyStatus: Equatable {
        case empty
        case unsaved
        case testing
        case verified
        case failed(String)
        case saved
    }
    @State private var apiKeyStatus: ApiKeyStatus = .empty

    // Provider 预设（4 个，统一入口，1 次点击设齐 URL+QueryMode+Router+RouteModel+Streaming+Failover）
    private enum ProviderPreset: String, CaseIterable, Identifiable {
        case freeModel = "FreeModel"
        case deepseek = "DeepSeek"
        case openRouter = "OpenRouter"
        case modelScope = "ModelScope"
        var id: String { rawValue }

        struct Config {
            let apiURL: String
            let dashboardURL: String
            let queryMode: QueryMode
            let routerUpstream: String
            let defaultModel: String
            let routeModel: String
        }

        var config: Config {
            switch self {
            case .freeModel:
                return .init(apiURL: "https://api.freemodel.dev",
                             dashboardURL: "https://freemodel.dev",
                             queryMode: .dashboard,
                             routerUpstream: "https://api.freemodel.dev/v1",
                             defaultModel: "codex-mini",
                             routeModel: "codex-mini")
            case .deepseek:
                return .init(apiURL: "https://api.deepseek.com",
                             dashboardURL: "https://platform.deepseek.com",
                             queryMode: .apiKey,
                             routerUpstream: "https://api.deepseek.com/v1",
                             defaultModel: "deepseek-chat",
                             routeModel: "codex-mini")
            case .openRouter:
                return .init(apiURL: "https://openrouter.ai/api/v1",
                             dashboardURL: "https://openrouter.ai",
                             queryMode: .apiKey,
                             routerUpstream: "https://openrouter.ai/api/v1",
                             defaultModel: "deepseek/deepseek-v4-flash:free",
                             routeModel: "codex-mini")
            case .modelScope:
                return .init(apiURL: "https://api-inference.modelscope.cn",
                             dashboardURL: "https://modelscope.cn",
                             queryMode: .apiKey,
                             routerUpstream: "https://api-inference.modelscope.cn/v1",
                             defaultModel: "ZhipuAI/GLM-5.1",
                             routeModel: "codex-mini")
            }
        }
    }

    // 自定义 URL / 预设切换反馈（原本借用 apiKeySection 的 showTestResult，跨区段渲染看不到）
    private struct UrlPresetStatus: Equatable {
        let success: Bool
        let message: String
    }
    @State private var urlPresetStatus: UrlPresetStatus? = nil
    @State private var renameText: String = ""
    @State private var apiURLInput: String = ""
    @State private var dashboardURLInput: String = ""

    // 账号 sidebar state
    @State private var addExpanded: AddKind? = nil
    @State private var newAccountLabel: String = ""

    // Codex 注入 sidebar state
    @State private var newCodexLabel: String = ""
    @State private var newCodexProvider: String = ""

    // 删除确认
    @State private var pendingDeleteAccount: ProviderAccount? = nil
    @State private var pendingDeleteCodexConfig: InjectionConfiguration? = nil

    // 详情区 3 段展开状态（已全部默认展开：3 段是平等逻辑，不再折叠）
    @State private var isAccountGroupExpanded: Bool = true
    @State private var isConnectionGroupExpanded: Bool = true
    @State private var isRouterGroupExpanded: Bool = true

    // 日志清除 toast
    @State private var logsClearedToast: String? = nil
    @State private var logsClearedToastToken: Int = 0

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

                                // 3 段平等逻辑：始终展开，用 Label + Divider 分段（不再折叠）
                                sectionHeader("账号", systemImage: "person.text.rectangle")
                                VStack(alignment: .leading, spacing: 18) {
                                    accountDetails(account)
                                    queryModeSection(account)
                                    linksSection(account)
                                }

                                Divider().padding(.vertical, 4)

                                sectionHeader("连接", systemImage: "link")
                                VStack(alignment: .leading, spacing: 18) {
                                    dashboardSection(account)
                                    apiKeySection(account)
                                }

                                Divider().padding(.vertical, 4)

                                sectionHeader("路由", systemImage: "arrow.triangle.2.circlepath")
                                VStack(alignment: .leading, spacing: 18) {
                                    routerSection(account)
                                    customURLsSection(account)
                                    refreshSection
                                }
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
            apiKeyStatus = .unsaved
            urlPresetStatus = nil
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
                accountsSection
                codexSection
                logsSection
            }
            .listStyle(.sidebar)
        }
        .confirmationDialog(
            "确定删除账号 “\(pendingDeleteAccount?.displayName ?? "")” ？",
            isPresented: Binding(
                get: { pendingDeleteAccount != nil },
                set: { if !$0 { pendingDeleteAccount = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeleteAccount
        ) { acct in
            Button("删除 “\(acct.displayName)”", role: .destructive) {
                _ = accountManager.deleteAccount(id: acct.id)
                balanceManager.syncFromActiveAccount()
                if case .account(let id) = selectedItem, id == acct.id {
                    selectedItem = nil
                }
                pendingDeleteAccount = nil
            }
            Button("取消", role: .cancel) {
                pendingDeleteAccount = nil
            }
        } message: { _ in
            Text("该账号的 API Key、控制台登录态与本地缓存余额将一并清除。此操作不可撤销。")
        }
        .confirmationDialog(
            "确定删除注入配置 “\(pendingDeleteCodexConfig?.label ?? "")” ？",
            isPresented: Binding(
                get: { pendingDeleteCodexConfig != nil },
                set: { if !$0 { pendingDeleteCodexConfig = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeleteCodexConfig
        ) { cfg in
            Button("删除 “\(cfg.label)”", role: .destructive) {
                codexInjectionLayer.deleteConfiguration(id: cfg.id)
                if case .codexInjectionConfig(let id) = selectedItem, id == cfg.id {
                    selectedItem = nil
                }
                pendingDeleteCodexConfig = nil
            }
            Button("取消", role: .cancel) {
                pendingDeleteCodexConfig = nil
            }
        } message: { _ in
            Text("将清除本条注入的 auth.json 与 config.toml 编辑内容；已激活的注入将被先恢复默认。此操作不可撤销。")
        }
    }


    // MARK: - 3 个侧边栏 Section（抽成独立视图避免 List 类型推断超时）

    private var accountsSection: some View {
        Section(header: accountsSectionHeader) {
            if addExpanded == .account {
                accountsInlineAddRow
            }
            ForEach(accountManager.accounts) { account in
                accountListRow(account)
            }
        }
    }

    private var codexSection: some View {
        Section(header: codexSectionHeader) {
            if addExpanded == .codex {
                codexInlineAddRow
            }
            ForEach(codexInjectionLayer.injectionConfigurations) { cfg in
                codexConfigListRow(cfg)
            }
        }
    }

    private var logsSection: some View {
        Section(header: Text("运行日志")) {
            SidebarRow(
                icon: "terminal.fill",
                iconColor: routerStatusColor(routerManager.status) ?? .secondary,
                title: "运行日志",
                subtitle: routerStatusSubtitle,
                statusColor: routerStatusColor(routerManager.status),
                isSelected: {
                    if case .logs = selectedItem { return true }
                    return false
                }()
            )
        }
    }
    // MARK: - 侧边栏行 helper（含 contextMenu，避免 ForEach 体内 type-check 累积）

    private func accountListRow(_ account: ProviderAccount) -> some View {
        accountRow(account)
            .tag(SidebarItem.account(account.id))
            .contextMenu {
                Button(role: .destructive) {
                    pendingDeleteAccount = account
                } label: {
                    Label("删除账号", systemImage: "trash")
                }
            }
    }

    private func codexConfigListRow(_ cfg: InjectionConfiguration) -> some View {
        codexConfigRow(cfg)
            .tag(SidebarItem.codexInjectionConfig(cfg.id))
            .contextMenu {
                Button {
                    codexInjectionLayer.activateConfiguration(id: cfg.id)
                } label: {
                    Label("激活", systemImage: "bolt.fill")
                }
                Button(role: .destructive) {
                    pendingDeleteCodexConfig = cfg
                } label: {
                    Label("删除", systemImage: "trash")
                }
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
            VStack(alignment: .leading, spacing: 4) {
                Text("种类").frame(maxWidth: .infinity, alignment: .leading).font(.caption).foregroundStyle(.secondary)
                // 2×2 网格：4 个 provider 各占一格，避开 220px 侧栏拥挤
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6)
                ], spacing: 6) {
                    Button {
                        let account = accountManager.createAccount(displayName: newAccountLabel, providerID: "freemodel")
                        accountManager.selectAccount(id: account.id)
                        balanceManager.syncFromActiveAccount()
                        addExpanded = nil
                    } label: {
                        Label("FreeModel 网页", systemImage: "globe")
                            .frame(maxWidth: .infinity)
                    }
                    Button {
                        let account = accountManager.createAccount(displayName: newAccountLabel, providerID: "deepseek")
                        accountManager.selectAccount(id: account.id)
                        balanceManager.syncFromActiveAccount()
                        addExpanded = nil
                    } label: {
                        Label("DeepSeek API", systemImage: "key.fill")
                            .frame(maxWidth: .infinity)
                    }
                    Button {
                        let account = accountManager.createAccount(displayName: newAccountLabel, providerID: "openrouter")
                        accountManager.selectAccount(id: account.id)
                        balanceManager.syncFromActiveAccount()
                        addExpanded = nil
                    } label: {
                        Label("OpenRouter API", systemImage: "arrow.triangle.branch")
                            .frame(maxWidth: .infinity)
                    }
                    Button {
                        let account = accountManager.createAccount(displayName: newAccountLabel, providerID: "modelscope")
                        accountManager.selectAccount(id: account.id)
                        balanceManager.syncFromActiveAccount()
                        addExpanded = nil
                    } label: {
                        Label("ModelScope API", systemImage: "cube")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            HStack {
                Spacer()
                Button("取消") {
                    addExpanded = nil
                }
            }
        }
        .font(.caption)
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
            VStack(alignment: .leading, spacing: 4) {
                Text("种类").frame(maxWidth: .infinity, alignment: .leading).font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6)
                ], spacing: 6) {
                    Button {
                        codexInjectionLayer.prepareOfficialLoginSession(label: newCodexLabel)
                        addExpanded = nil
                    } label: {
                        Label("官方", systemImage: "person.crop.circle.badge.checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    Button {
                        codexInjectionLayer.addEmptyThirdPartyConfiguration(label: newCodexLabel, providerID: newCodexProvider)
                        addExpanded = nil
                    } label: {
                        Label("第三方", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            HStack {
                Spacer()
                Button("取消") {
                    addExpanded = nil
                }
            }
        }
        .font(.caption)
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
        var isSelected: Bool = false

        init(icon: String,
             iconColor: Color = .secondary,
             title: String,
             subtitle: String? = nil,
             statusColor: Color? = nil,
             subtitleColor: Color = .secondary,
             isSelected: Bool = false) {
            self.icon = icon
            self.iconColor = iconColor
            self.title = title
            self.subtitle = subtitle
            self.statusColor = statusColor
            self.subtitleColor = subtitleColor
            self.isSelected = isSelected
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
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .contentShape(Rectangle())
        }
    }
    // MARK: - 单条注入配置行

    private func codexConfigRow(_ cfg: InjectionConfiguration) -> some View {
        let isActive = (codexInjectionLayer.activeInjection?.configurationID == cfg.id)
        let isSelected: Bool = {
            if case .codexInjectionConfig(let selectedID) = selectedItem, selectedID == cfg.id {
                return true
            }
            return false
        }()
        return SidebarRow(
            icon: isActive ? "checkmark.circle.fill" : "circle",
            iconColor: isActive ? .green : .secondary,
            title: cfg.label,
            subtitle: "\(cfg.kind == .official ? "官方" : "第三方") · \(cfg.providerID)",
            statusColor: isActive ? .green : nil,
            isSelected: isSelected
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

        // 切到不同账号时，重置 API Key / URL 预设状态（避免上一个账号的提示泄漏）
        apiKeyStatus = .unsaved
        urlPresetStatus = nil
	    }

    private func accountRow(_ account: ProviderAccount) -> some View {
        SidebarRow(
            icon: account.hasDashboardSession ? "checkmark.circle.fill" : "person.crop.circle",
            iconColor: account.hasDashboardSession ? .green : .secondary,
            title: account.displayName,
            subtitle: accountStatusText(account),
            isSelected: isAccountSelected(account.id)
        )
    }

    private func isAccountSelected(_ id: UUID) -> Bool {
        if case .account(let selectedID) = selectedItem, selectedID == id {
            return true
        }
        return false
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
        routerStatusColor(routerManager.status)
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
                .font(.headline)

	            Text("API Key 按账号单独保存，可用于当前账号的余额查询和本地 Responses 路由代理。测试连接成功后会自动保存。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .center, spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
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
                    apiKeyStatusBadge
                        .padding(6)
                }

                Button(action: { showAPIKey.toggle() }) {
                    Image(systemName: showAPIKey ? "eye.slash" : "eye")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .disabled(isTesting)
                .help(showAPIKey ? "隐藏 API Key" : "显示 API Key")

                if isTesting {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 28, height: 28)
                        .help("正在测试连接")
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

                Button("清除 API Key") {
                    balanceManager.apiKey = nil
                    apiKeyInput = ""
                    apiKeyStatus = .empty
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .frame(height: 28)
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

            Text("控制台模式自动重新抓取余额的频率。API Key 模式不消耗此设置。")
                .font(.caption2)
                .foregroundStyle(.secondary)
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

    private func deleteActiveAccount() {
        guard let account = accountManager.activeAccount else { return }
        _ = accountManager.deleteAccount(id: account.id)
        apiKeyInput = ""
        balanceManager.syncFromActiveAccount()
    }

    private func accountStatusText(_ account: ProviderAccount) -> String {
        // 统一格式：有余额 = "余额 · 状态"；无余额 = "状态"
        let status: String
        switch account.queryMode {
        case .dashboard:
            status = account.hasDashboardSession ? "控制台已登录" : "控制台未登录"
        case .apiKey:
            status = account.hasAPIKey ? "已设 Key" : "未设 Key"
        }
        if let balance = account.lastBalance {
            return "\(balance.remainingFormatted) · \(status)"
        }
        return status
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

    private func customURLsSection(_ account: ProviderAccount) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("自定义服务器地址", systemImage: "network")
                .font(.headline)

            Text("要快速切换 provider（URL + 查询模式 + 路由 + 默认模型 一次性设齐）？请到下方「路由」段顶部选择预设。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
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
                urlPresetStatus = UrlPresetStatus(success: true, message: "服务器地址已保存")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .frame(height: 28)
            .disabled(apiURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                      dashboardURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            urlPresetStatusBadge
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


    // MARK: - 统一 provider 预设入口（1 次点击设齐 6 个字段）

    private func applyProviderPreset(_ preset: ProviderPreset, for account: ProviderAccount) {
        let cfg = preset.config
        // 写账号层
        accountManager.updateURLs(apiURL: cfg.apiURL, dashboardURL: cfg.dashboardURL, for: account.id)
        accountManager.updateQueryMode(cfg.queryMode, for: account.id)
        // 同步 router @State（用户当下能直接看到变化）
        routerUpstreamURL = cfg.routerUpstream
        routerDefaultModel = cfg.defaultModel
        routerRouteModel = cfg.routeModel
        routerStreaming = true
        routerFailoverEnabled = true
        saveRouterSettings()
        // 重新拉 @State
        loadFieldsFromActiveAccount()
        // 反馈
        urlPresetStatus = UrlPresetStatus(success: true, message: "已切换为 \(preset.rawValue) 预设")
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

    private func toggleLabel(routerEnabled: Bool, hasAPIKey: Bool) -> String {
        if !hasAPIKey { return "请先配置 API Key" }
        return routerEnabled ? "正在运行代理" : "启用本地路由代理"
    }

    // MARK: - Router Section

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
                    Text(toggleLabel(routerEnabled: routerEnabled, hasAPIKey: account.hasAPIKey))
                        .fontWeight(.semibold)
                        .foregroundStyle(account.hasAPIKey ? Color.primary : .red)
                }
                .disabled(!account.hasAPIKey)

                Spacer()
            }
            .padding(.vertical, 4)

            // 1 套统一 provider 预设 chip（4 个，1 次点击设齐 URL+QueryMode+Router+RouteModel+Streaming+Failover）
            HStack(spacing: 6) {
                Text("预设:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(ProviderPreset.allCases) { preset in
                    Button(preset.rawValue) {
                        applyProviderPreset(preset, for: account)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.bottom, 4)

            if routerEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Text("带")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("*")
                            .font(.caption2)
                            .foregroundStyle(.red)
                        Text("的字段不能为空。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    // 3 个重复 provider 按钮已删除（统一到 Toggle 下方 1 套 chip）
                    
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 2) {
                                Text("本地代理端口")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if routerFieldEmpty(routerPort) {
                                    Text("*").font(.caption2).foregroundStyle(.red)
                                }
                            }
                            TextField("38440", text: $routerPort)
                                .textFieldStyle(.roundedBorder)
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(routerFieldEmpty(routerPort) ? .red.opacity(0.6) : .clear, lineWidth: 1.5))
                                .frame(width: 80)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 2) {
                                Text("对外暴露模型名")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if routerFieldEmpty(routerRouteModel) {
                                    Text("*").font(.caption2).foregroundStyle(.red)
                                }
                            }
                            TextField("codex-mini", text: $routerRouteModel)
                                .textFieldStyle(.roundedBorder)
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(routerFieldEmpty(routerRouteModel) ? .red.opacity(0.6) : .clear, lineWidth: 1.5))
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 2) {
                            Text("上游 API Base URL")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if routerFieldEmpty(routerUpstreamURL) {
                                Text("*").font(.caption2).foregroundStyle(.red)
                            }
                        }
                        TextField("https://api.deepseek.com/v1", text: $routerUpstreamURL)
                            .textFieldStyle(.roundedBorder)
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(routerFieldEmpty(routerUpstreamURL) ? .red.opacity(0.6) : .clear, lineWidth: 1.5))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 2) {
                            Text("映射到上游模型名")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if routerFieldEmpty(routerDefaultModel) {
                                Text("*").font(.caption2).foregroundStyle(.red)
                            }
                        }
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

                    // Toggle 一行，按钮单独一行右侧
                    HStack(spacing: 20) {
                        Toggle("流式响应 (Streaming)", isOn: $routerStreaming)
                            .font(.caption)
                        Toggle("自动灾备转移 (Failover)", isOn: $routerFailoverEnabled)
                            .font(.caption)
                        Spacer()
                    }
                    HStack {
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
        VStack(alignment: .leading, spacing: 6) {
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
                if routerManager.status == .running, let activeAccount = accountManager.activeAccount {
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        let portVal = activeAccount.activeRouterSettings.port
                        NSPasteboard.general.setString("http://127.0.0.1:\(portVal)/v1", forType: .string)
                    }) {
                        Label("复制 Base URL", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            // 三段式：账号 / 监听 / 上游（每段独立换行不重叠）
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
            // 日志控制：复制 / 清除
            HStack(spacing: 12) {
                Button(action: copyAllLogs) {
                    Label("复制所有日志", systemImage: "doc.on.doc.fill")
                }
                .buttonStyle(.bordered)
                .disabled(routerManager.logs.isEmpty)

                Button(action: clearLogsWithToast) {
                    Label("清除日志", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(routerManager.logs.isEmpty)

                if let toast = logsClearedToast {
                    Text(toast)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
                Spacer()
            }

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

    private func clearLogsWithToast() {
        let count = routerManager.logs.count
        routerManager.logs.removeAll()
        if count == 0 {
            logsClearedToast = "当前无日志"
        } else {
            logsClearedToast = "已清除 \(count) 条日志"
            // 3 秒后自动隐藏
            logsClearedToastToken &+= 1
            let token = logsClearedToastToken
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if logsClearedToastToken == token {
                    withAnimation { logsClearedToast = nil }
                }
            }
        }
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

    // MARK: - 详情区段头（始终展开，3 段平等逻辑共用）

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .padding(.top, 4)
    }

    // MARK: - 路由状态颜色（顶栏 / 详情区 / 日志行 共用单一来源）

    private func routerStatusColor(_ status: RouterStatus) -> Color? {
        switch status {
        case .running: return .green
        case .starting: return .orange
        case .failed, .portInUse, .missingKey: return .red
        case .off: return nil
        }
    }

    // MARK: - API Key 状态徽章（内嵌文本框右下角，统一 22pt 高，0.2s 淡入）

    @ViewBuilder
    private var apiKeyStatusBadge: some View {
        let pair: (icon: String, color: Color, text: String)? = {
            switch apiKeyStatus {
            case .empty: return nil
            case .unsaved: return ("circle", .secondary, "未保存")
            case .testing: return nil  // testing 期间 ProgressView 已经在外侧显示
            case .verified: return ("checkmark.seal.fill", .green, "已验证")
            case .failed(let msg): return ("xmark.octagon.fill", .red, msg)
            case .saved: return ("checkmark.circle", .blue, "已保存")
            }
        }()
        if let pair {
            HStack(spacing: 4) {
                Image(systemName: pair.icon)
                    .font(.caption2)
                Text(pair.text)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .foregroundStyle(pair.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(pair.color.opacity(0.12))
            )
            .frame(height: 22)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: apiKeyStatus)
        }
    }

    // MARK: - URL 预设切换反馈徽章（内嵌 customURLsSection 末尾）

    @ViewBuilder
    private var urlPresetStatusBadge: some View {
        if let status = urlPresetStatus {
            HStack(spacing: 4) {
                Image(systemName: status.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.caption2)
                Text(status.message)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .foregroundStyle(status.success ? .green : .red)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill((status.success ? Color.green : Color.red).opacity(0.12))
            )
            .frame(height: 22)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: urlPresetStatus)
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
