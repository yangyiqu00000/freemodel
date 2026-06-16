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
    @State private var urlPresetStatusToken: Int = 0
    @State private var renameText: String = ""
    @State private var initialDisplayName: String = ""
    @State private var initialApiURL: String = ""
    @State private var initialDashboardURL: String = ""
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
    @State private var pendingRenameAccount: ProviderAccount? = nil
    @State private var renameInput: String = ""
    @State private var pendingDeleteCodexConfig: InjectionConfiguration? = nil

    // 日志清除 toast
    @State private var logsClearedToast: String? = nil
    @State private var pendingScrollToAPIKey: Bool = false
    @State private var logsClearedToastToken: Int = 0
    // 复制 Base URL toast
    @State private var baseURLCopiedToast: String? = nil
    @State private var baseURLCopiedToastToken: Int = 0

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

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
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

                                Divider().padding(.vertical, 4)

                                sectionHeader("连接", systemImage: "link", statusColor: connectionHeaderStatusColor(account))
                                sectionVStack {
                                    dashboardSection(account)
                                    apiKeySection(account)
                                }

                                Divider().padding(.vertical, 4)

                                sectionHeader("路由", systemImage: "arrow.triangle.2.circlepath.circle", statusColor: routerHeaderStatusColor())
                                sectionVStack {
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
                            CodexInjectionSettingsView(
                                appLayer: codexInjectionLayer,
                                configurationID: cfgID,
                                pendingDeleteCodexConfig: $pendingDeleteCodexConfig
                            )
                        }
                    } else {
                        emptyState
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
        .alert(
            "重命名账号",
            isPresented: Binding(
                get: { pendingRenameAccount != nil },
                set: { if !$0 { pendingRenameAccount = nil } }
            ),
            presenting: pendingRenameAccount
        ) { acct in
            TextField("新名称", text: $renameInput)
                .textFieldStyle(.roundedBorder)
            Button("保存") {
                let trimmed = renameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    accountManager.renameAccount(id: acct.id, displayName: trimmed)
                }
                pendingRenameAccount = nil
            }
            Button("取消", role: .cancel) {
                pendingRenameAccount = nil
            }
        } message: { acct in
            Text("当前名称：\(acct.displayName)")
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
        Section(header: sidebarSectionHeader(title: "运行日志", systemImage: "terminal.fill", trailing: nil)) {
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
                Button {
                    renameInput = account.displayName
                    pendingRenameAccount = account
                } label: {
                    Label("重命名", systemImage: "pencil")
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(account.displayName, forType: .string)
                } label: {
                    Label("复制账号名", systemImage: "doc.on.doc.fill")
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(account.providerID, forType: .string)
                } label: {
                    Label("复制 Provider", systemImage: "doc.on.doc.fill")
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(account.id.uuidString, forType: .string)
                } label: {
                    Label("复制账号 ID", systemImage: "doc.on.doc.fill")
                }
                if account.id != accountManager.activeAccountID {
                    Divider()
                    Button {
                        accountManager.selectAccount(id: account.id)
                        balanceManager.syncFromActiveAccount()
                    } label: {
                        Label("设为活跃账号", systemImage: "checkmark.circle.fill")
                    }
                }
                Divider()
                Button(role: .destructive) {
                    pendingDeleteAccount = account
                } label: {
                    Label("删除账号", systemImage: "trash.fill")
                }
            }
    }

    private func codexConfigListRow(_ cfg: InjectionConfiguration) -> some View {
        codexConfigRow(cfg)
            .tag(SidebarItem.codexInjectionConfig(cfg.id))
            .contextMenu {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cfg.label, forType: .string)
                } label: {
                    Label("复制 label", systemImage: "doc.on.doc.fill")
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cfg.providerID, forType: .string)
                } label: {
                    Label("复制 Provider", systemImage: "doc.on.doc.fill")
                }
                Divider()
                Button {
                    codexInjectionLayer.activateConfiguration(id: cfg.id)
                } label: {
                    Label("激活", systemImage: "bolt.fill")
                }
                Divider()
                Button(role: .destructive) {
                    pendingDeleteCodexConfig = cfg
                } label: {
                    Label("删除", systemImage: "trash.fill")
                }
            }
    }


    // MARK: - 账号 section 标题（与 Codex 注入同形状：label + 右侧 +）

    private var accountsSectionHeader: some View {
        sidebarSectionHeader(
            title: "账号",
            systemImage: "person.2.fill",
            trailing: AnyView(
                Button {
                    addExpanded = (addExpanded == .account) ? nil : .account
                    if addExpanded == .account {
                        newAccountLabel = "新账号 \(Self.shortNow())"
                    }
                } label: {
                    Image(systemName: addExpanded == .account ? "minus" : "plus")
                }
                .buttonStyle(.borderless)
                .help(addExpanded == .account ? "收起添加账号行" : "新增账号")
            )
        )
    }
    // MARK: - 内联账号添加行（与 codexInlineAddRow 同形状）

    private var accountsInlineAddRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                fieldLabel("名称")
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
        .addRowPanel()
    }

    private var codexSectionHeader: some View {
        sidebarSectionHeader(
            title: "Codex 注入",
            systemImage: "key.horizontal.fill",
            trailing: AnyView(
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
                .help(addExpanded == .codex ? "收起添加注入配置行" : "添加一条新的注入配置")
            )
        )
    }
    // MARK: - 内联添加行（替代 sheet）

    private var codexInlineAddRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                fieldLabel("标签")
                TextField("例如：本地 relay", text: $newCodexLabel)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                fieldLabel("Provider")
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
        .addRowPanel()
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
        @State private var isHovered: Bool = false

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
                    .fill(backgroundFill)
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
            }
        }

        //  优先级：选中 (accent 0.18) > hover (secondary 0.10) > 透明
        private var backgroundFill: Color {
            if isSelected { return Color.accentFill }
            if isHovered  { return Color.secondary.opacity(0.10) }
            return Color.clear
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
	        initialDisplayName = account.displayName
	        apiURLInput = account.apiBaseURL
	        dashboardURLInput = account.dashboardURL
	        initialApiURL = account.apiBaseURL
	        initialDashboardURL = account.dashboardURL
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
        navHeader(
            icon: "gearshape.fill",
            tint: .blue,
            title: "FreeModel 设置",
            subtitle: headerSubtitle,
            dotColor: headerStatusDot
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

    private var headerStatusDot: Color? {
        routerStatusColor(routerManager.status)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text("还没有账号")
                .font(.headline)
            Text("点击侧边栏右上角的 + 添加账号")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
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
                        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        accountManager.renameAccount(id: account.id, displayName: trimmed)
                        initialDisplayName = trimmed
                    }
                Button("重命名") {
                    let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    accountManager.renameAccount(id: account.id, displayName: trimmed)
                    initialDisplayName = trimmed
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
            status = account.hasAPIKey ? "已设 API Key" : "未设 API Key"
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
                HStack(spacing: 4) {
                    Text("控制台网页 Base URL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if dashboardURLInput.trimmingCharacters(in: .whitespacesAndNewlines) != initialDashboardURL {
                        Image(systemName: "circle.dashed")
                            .foregroundStyle(.orange)
                            .imageScale(.small)
                        Text("未保存")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                TextField("https://freemodel.dev", text: $dashboardURLInput)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text("API Base URL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if apiURLInput.trimmingCharacters(in: .whitespacesAndNewlines) != initialApiURL {
                        Image(systemName: "circle.dashed")
                            .foregroundStyle(.orange)
                            .imageScale(.small)
                        Text("未保存")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                TextField("https://api.freemodel.dev", text: $apiURLInput)
                    .textFieldStyle(.roundedBorder)
            }

            Button("保存服务器地址") {
                accountManager.updateURLs(apiURL: apiURLInput, dashboardURL: dashboardURLInput, for: account.id)
                initialApiURL = apiURLInput
                initialDashboardURL = dashboardURLInput
                triggerUrlPresetStatus(UrlPresetStatus(success: true, message: "服务器地址已保存"))
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
	            .background(Capsule().fill(Color.overlayFill))
	    }

	    private func providerName(_ account: ProviderAccount) -> String {
	        if account.providerID == "deepseek" || account.apiBaseURL.lowercased().contains("deepseek") {
	            return "DeepSeek"
	        }
	        return "FreeModel"
	    }


    // MARK: - 统一 provider 预设入口（1 次点击设齐 6 个字段）

    private func isPresetActive(_ preset: ProviderPreset, for account: ProviderAccount) -> Bool {
        // 4 个 preset 的 apiURL 互不相同，仅用 apiBaseURL 一字段就能完整区分
        return account.apiBaseURL == preset.config.apiURL
    }

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
        triggerUrlPresetStatus(UrlPresetStatus(success: true, message: "已切换为 \(preset.rawValue) 预设"))
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

            // 缺 API Key 提示卡片（Toggle 禁用 + 视觉警告 + 引导去连接段配置）
            if !account.hasAPIKey {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("未配置 API Key")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.red)
                        Text("启用本地路由代理需要 API Key，请先在上方「连接」段配置并测试。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("去配置") {
                        // 触发 onChange 走 proxy.scrollTo（apiKeySection 头部已加 .id 锚点）
                        pendingScrollToAPIKey = true
                        apiKeyStatus = .empty
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.orange)
                    .help("向上滚动到「连接」段配置 API Key")
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.red.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
                .padding(.bottom, 4)
            }

            // 1 套统一 provider 预设 chip（4 个，1 次点击设齐 URL+QueryMode+Router+RouteModel+Streaming+Failover）
            HStack(spacing: 6) {
                Text("预设:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(ProviderPreset.allCases) { preset in
                    if isPresetActive(preset, for: account) {
                        Button(preset.rawValue) {
                            applyProviderPreset(preset, for: account)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .help("当前账号正在使用此预设")
                    } else {
                        Button(preset.rawValue) {
                            applyProviderPreset(preset, for: account)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("1 次点击套用 \(preset.rawValue) 的 URL+查询模式+路由+默认模型+Streaming+Failover")
                    }
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
                    
                    // 4 个输入字段按语义拆 2 组：代理设置（端口+上游URL） / 模型映射（对外+映射）
                    VStack(alignment: .leading, spacing: 8) {
                        Label("代理设置", systemImage: "network")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                        }
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.05)))

                    VStack(alignment: .leading, spacing: 8) {
                        Label("模型映射", systemImage: "arrow.left.arrow.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.05)))

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
                        .controlSize(.regular)
                        .frame(height: 28)
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
                navHeader(
                    icon: "terminal.fill",
                    tint: .green,
                    title: "路由代理运行日志",
                    subtitle: routerStatusSubtitle,
                    dotColor: headerStatusDot
                )
                if let activeAccount = accountManager.activeAccount {
                    let isRunning = routerManager.status == .running
                    let portVal = activeAccount.activeRouterSettings.port
                    let urlString = "http://127.0.0.1:\(portVal)/v1"
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(urlString, forType: .string)
                        triggerBaseURLCopiedToast()
                    }) {
                        Label("复制 Base URL", systemImage: "doc.on.doc.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!isRunning)
                    .help(isRunning ? "复制 \(urlString) 到剪贴板" : "启动路由代理后才可复制 Base URL")
                    if let toast = baseURLCopiedToast {
                        StatusBadge(icon: "doc.on.doc.fill", text: toast, tint: .blue)
                            .transition(.opacity)
                    }
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

                if let toast = logsClearedToast {
                    StatusBadge(icon: "trash.fill", text: toast, tint: .secondary)
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

    private func triggerBaseURLCopiedToast() {
        baseURLCopiedToast = "Base URL 已复制"
        // 3 秒后自动隐藏
        baseURLCopiedToastToken &+= 1
        let token = baseURLCopiedToastToken
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if baseURLCopiedToastToken == token {
                withAnimation { baseURLCopiedToast = nil }
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
        case .portInUse: return "端口占用"
        case .missingKey: return "请先配置 API Key"
        }
    }

    // MARK: - 详情区段头（始终展开，3 段平等逻辑共用）

    /// 内联添加行字段标签：56pt 固定宽 + caption 灰底（与右侧 TextField 对齐），3 处共用
    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .frame(width: 56, alignment: .leading)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// 侧边栏 section header（Label + headline + trailing 可选 + button），3 处共用
    private func sidebarSectionHeader(title: String, systemImage: String, trailing: AnyView?) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Spacer()
            if let trailing = trailing {
                trailing
            }
        }
    }

    /// 详情区顶部 nav header（icon + title2 bold 标题 + caption 副标题 + 可选 dot），2 处共用
    private func navHeader(icon: String, tint: Color, title: String, subtitle: String, dotColor: Color? = nil) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                HStack(spacing: 6) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let color = dotColor {
                        Circle()
                            .fill(color)
                            .frame(width: 6, height: 6)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String, systemImage: String, statusColor: Color? = nil) -> some View {
        HStack(spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Spacer()
            if let color = statusColor {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .help(headerDotHelp(for: title))
            }
        }
        .padding(.top, 4)
    }

    // MARK: - 详情区 header status dot help（按段标题返回对应解释）

    private func headerDotHelp(for title: String) -> String {
        switch title {
        case "账号": return "账号信息已配置"
        case "连接": return "控制台已登录且 API Key 已配置"
        case "路由": return routerStatusSubtitle
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

    private func routerHeaderStatusColor() -> Color? {
        // 路由段：复用 routerStatusColor
        return routerStatusColor(routerManager.status)
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

    // MARK: - URL 预设切换反馈徽章（内嵌 customURLsSection 末尾）

    @ViewBuilder
    private var urlPresetStatusBadge: some View {
        if let status = urlPresetStatus {
            StatusBadge(
                icon: status.success ? "checkmark.circle.fill" : "xmark.circle.fill",
                text: status.message,
                tint: status.success ? .green : .red
            )
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: urlPresetStatus)
        }
    }

    private func triggerUrlPresetStatus(_ status: UrlPresetStatus) {
        urlPresetStatus = status
        // 3 秒后自动隐藏（与 logsClearedToast / baseURLCopiedToast 同模式，token 防过期 toast 复活）
        urlPresetStatusToken &+= 1
        let token = urlPresetStatusToken
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if urlPresetStatusToken == token {
                withAnimation { urlPresetStatus = nil }
            }
        }
    }
}

private extension View {
    /// 详情区段背景（gray 8pt 圆角 panel）——8 处统一使用
    func sectionPanel() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.surfaceElevatedFill))
    }

    /// 详情区 3 段内部 VStack（与 sectionPanel 内部 padding 16 对齐）
    func sectionVStack<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16, content: content)
    }

    /// 侧边栏内联添加行背景（blue 6pt 圆角小卡片）——2 处统一使用（账号 + Codex 注入）
    func addRowPanel() -> some View {
        self
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.blue.opacity(0.08))
            )
    }
}
