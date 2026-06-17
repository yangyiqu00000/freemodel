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

    @State private var renameText: String = ""
    @State private var initialDisplayName: String = ""

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

    @State private var pendingScrollToAPIKey: Bool = false
    // 添加账号 toast（账号 4 chip 共用）
    @State private var accountCreatedToast: String? = nil
    // 添加 Codex 注入 toast（官方 / 第三方 共用）
    @State private var codexConfigCreatedToast: String? = nil
    @State private var toastTask: Task<Void, Never>?

    // Router State（已移至 RouterSettingsView 的 RouterEditingState）

    var body: some View {
        HStack(spacing: 0) {
            accountList
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
                            selectAccountAndSync(id: uuid)
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
            isPresented: .nilify($pendingDeleteAccount),
            titleVisibility: .visible,
            presenting: pendingDeleteAccount
        ) { acct in
            Button("删除 “\(acct.displayName)”", role: .destructive) {
                deleteAccountAndSync(id: acct.id, clearDetailFields: false)
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
            isPresented: .nilify($pendingRenameAccount),
            presenting: pendingRenameAccount
        ) { acct in
            TextField("新名称", text: $renameInput)
                .textFieldStyle(.roundedBorder)
            Button("保存") {
                _ = commitRename(input: renameInput, accountID: acct.id)
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
            isPresented: .nilify($pendingDeleteCodexConfig),
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
                iconColor: routerManager.status.statusColor ?? .secondary,
                title: "运行日志",
                subtitle: routerManager.status.subtitle,
                statusColor: routerManager.status.statusColor,
                isSelected: {
                    if case .logs = selectedItem { return true }
                    return false
                }()
            )
            .tag(SidebarItem.logs)
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
                    ClipboardHelper.shared.copy(account.displayName)
                } label: {
                    Label("复制账号名", systemImage: "doc.on.doc.fill")
                }
                Button {
                    ClipboardHelper.shared.copy(account.providerID)
                } label: {
                    Label("复制 Provider", systemImage: "doc.on.doc.fill")
                }
                Button {
                    ClipboardHelper.shared.copy(account.id.uuidString)
                } label: {
                    Label("复制账号 ID", systemImage: "doc.on.doc.fill")
                }
                if account.id != accountManager.activeAccountID {
                    Divider()
                    Button {
                        selectAccountAndSync(id: account.id)
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
                    ClipboardHelper.shared.copy(cfg.label)
                } label: {
                    Label("复制 label", systemImage: "doc.on.doc.fill")
                }
                Button {
                    ClipboardHelper.shared.copy(cfg.providerID)
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
            trailing: addExpandedToggleButton(
                kind: .account,
                onExpand: { newAccountLabel = "新账号 \(Self.shortNow())" },
                helpExpand: "新增账号",
                helpCollapse: "收起添加账号行"
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
                        commitAccountCreation(providerID: "freemodel", providerDisplayName: "FreeModel 网页")
                    } label: {
                        Label("FreeModel 网页", systemImage: "globe")
                            .frame(maxWidth: .infinity)
                    }
                    Button {
                        commitAccountCreation(providerID: "deepseek", providerDisplayName: "DeepSeek API")
                    } label: {
                        Label("DeepSeek API", systemImage: "key.fill")
                            .frame(maxWidth: .infinity)
                    }
                    Button {
                        commitAccountCreation(providerID: "openrouter", providerDisplayName: "OpenRouter API")
                    } label: {
                        Label("OpenRouter API", systemImage: "arrow.triangle.branch")
                            .frame(maxWidth: .infinity)
                    }
                    Button {
                        commitAccountCreation(providerID: "modelscope", providerDisplayName: "ModelScope API")
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
            trailing: addExpandedToggleButton(
                kind: .codex,
                onExpand: {
                    newCodexLabel = "新配置 \(Self.shortNow())"
                    newCodexProvider = "custom-\(Self.shortNow())"
                },
                helpExpand: "添加一条新的注入配置",
                helpCollapse: "收起添加注入配置行"
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
                        if let newID = codexInjectionLayer.injectionConfigurations.last?.id {
                            selectedItem = .codexInjectionConfig(newID)
                        }
                        showToast("已添加：\(newCodexLabel) · 官方", at: $codexConfigCreatedToast)
                    } label: {
                        Label("官方", systemImage: "person.crop.circle.badge.checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    Button {
                        codexInjectionLayer.addEmptyThirdPartyConfiguration(label: newCodexLabel, providerID: newCodexProvider)
                        addExpanded = nil
                        if let newID = codexInjectionLayer.injectionConfigurations.last?.id {
                            selectedItem = .codexInjectionConfig(newID)
                        }
                        showToast("已添加：\(newCodexLabel) · 第三方", at: $codexConfigCreatedToast)
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
                    statusDot(color: statusColor, size: 7, help: "账号段：当前账号信息已配置")
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
	            apiKeyInput = ""
	            return
	        }

	        renameText = account.displayName
	        initialDisplayName = account.displayName
	        apiKeyInput = account.apiKey ?? ""
	        apiKeyStatus = .unsaved
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
                    openURL(account.dashboardURL)
                }
                .buttonStyle(.bordered)

                Button("API 文档") {
                    openURL(docURLString)
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
        deleteAccountAndSync(id: account.id, clearDetailFields: true)
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

// customURLsSection / providerPreset / routerSection / saveRouterSettings 已移至 RouterSettingsView.swift

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

    // MARK: - Logs Console View
    // 已提取至 LogsConsoleView.swift

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

    /// 内联添加行字段标签：56pt 固定宽 + caption 灰底（与右侧 TextField 对齐），3 处共用
    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .frame(width: 56, alignment: .leading)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// 侧边栏 +号折叠 toggle 按钮（账号 / Codex 注入 2 处共用）
    /// - kind: 要切换的 AddKind
    /// - onExpand: 用户点 + 触发后回调（用于预填默认 label / provider）
    /// - helpExpand / helpCollapse: 折叠/展开态的 help 文字
    private func addExpandedToggleButton(
        kind: AddKind,
        onExpand: @escaping () -> Void,
        helpExpand: String,
        helpCollapse: String
    ) -> AnyView {
        AnyView(
            Button {
                addExpanded = (addExpanded == kind) ? nil : kind
                if addExpanded == kind {
                    onExpand()
                }
            } label: {
                Image(systemName: addExpanded == kind ? "minus" : "plus")
            }
            .buttonStyle(.borderless)
            .help(addExpanded == kind ? helpCollapse : helpExpand)
        )
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

    // MARK: - 删除账号并同步 UI 状态（detail 字段清空开关可选，2 处共用）

    private func deleteAccountAndSync(id: UUID, clearDetailFields: Bool) {
        _ = accountManager.deleteAccount(id: id)
        balanceManager.syncFromActiveAccount()
        if clearDetailFields {
            apiKeyInput = ""
        }
        if case .account(let selID) = selectedItem, selID == id {
            selectedItem = nil
        }
    }

    // MARK: - 切换活跃账号并同步余额（selectAccount + syncFromActiveAccount 同一来源，3 处共用）

    private func selectAccountAndSync(id: UUID) {
        accountManager.selectAccount(id: id)
        balanceManager.syncFromActiveAccount()
    }

    // MARK: - 创建账号并选为活跃（4 个 provider chip 共用，1 行调用）

    private func commitAccountCreation(providerID: String, providerDisplayName: String) {
        let account = accountManager.createAccount(displayName: newAccountLabel, providerID: providerID)
        selectAccountAndSync(id: account.id)
        addExpanded = nil
        showToast("已添加：\(account.displayName) · \(providerDisplayName)", at: $accountCreatedToast)
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
