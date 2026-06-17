import SwiftUI

enum AddKind { case account, codex }

struct SettingsSidebarView: View {
    @Binding var selectedItem: SettingsView.SidebarItem?
    @ObservedObject var accountManager: AccountManager
    @ObservedObject var balanceManager: BalanceManager
    @ObservedObject var routerManager: RouterManager
    @ObservedObject var codexInjectionLayer: AppLayer
    @Binding var accountToast: String?
    @Binding var codexToast: String?
    @Binding var pendingDeleteCodexConfig: InjectionConfiguration?

    @State private var addExpanded: AddKind?
    @State private var newAccountLabel: String = ""
    @State private var newCodexLabel: String = ""
    @State private var newCodexProvider: String = ""
    @State private var pendingDeleteAccount: ProviderAccount?
    @State private var pendingRenameAccount: ProviderAccount?
    @State private var renameInput: String = ""

    var body: some View {
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
            "确定删除账号 \"\(pendingDeleteAccount?.displayName ?? "")\" ？",
            isPresented: .nilify($pendingDeleteAccount),
            titleVisibility: .visible,
            presenting: pendingDeleteAccount
        ) { acct in
            Button("删除 \"\(acct.displayName)\"", role: .destructive) {
                deleteAccountAndSync(id: acct.id)
                pendingDeleteAccount = nil
            }
            Button("取消", role: .cancel) { pendingDeleteAccount = nil }
        } message: { _ in
            Text("该账号的 API Key、控制台登录态与本地缓存余额将一并清除。此操作不可撤销。")
        }
        .alert(
            "重命名账号",
            isPresented: .nilify($pendingRenameAccount),
            presenting: pendingRenameAccount
        ) { acct in
            TextField("新名称", text: $renameInput).textFieldStyle(.roundedBorder)
            Button("保存") {
                commitRename(input: renameInput, accountID: acct.id)
                pendingRenameAccount = nil
            }
            Button("取消", role: .cancel) { pendingRenameAccount = nil }
        } message: { acct in
            Text("当前名称：\(acct.displayName)")
        }
        .confirmationDialog(
            "确定删除注入配置 \"\(pendingDeleteCodexConfig?.label ?? "")\" ？",
            isPresented: .nilify($pendingDeleteCodexConfig),
            titleVisibility: .visible,
            presenting: pendingDeleteCodexConfig
        ) { cfg in
            Button("删除 \"\(cfg.label)\"", role: .destructive) {
                codexInjectionLayer.deleteConfiguration(id: cfg.id)
                if case .codexInjectionConfig(let id) = selectedItem, id == cfg.id {
                    selectedItem = nil
                }
                pendingDeleteCodexConfig = nil
            }
            Button("取消", role: .cancel) { pendingDeleteCodexConfig = nil }
        } message: { _ in
            Text("将清除本条注入的 auth.json 与 config.toml 编辑内容；已激活的注入将被先恢复默认。此操作不可撤销。")
        }
    }

    private var accountsSection: some View {
        Section(header: accountsSectionHeader) {
            if addExpanded == .account { accountsInlineAddRow }
            ForEach(accountManager.accounts) { account in
                accountListRow(account)
            }
        }
    }

    private var codexSection: some View {
        Section(header: codexSectionHeader) {
            if addExpanded == .codex { codexInlineAddRow }
            ForEach(codexInjectionLayer.injectionConfigurations) { cfg in
                codexConfigListRow(cfg)
            }
        }
    }

    private var logsSection: some View {
        Section(header: sidebarSectionHeader(title: "运行日志", systemImage: "terminal.fill")) {
            SidebarRow(
                icon: "terminal.fill",
                iconColor: routerManager.status.statusColor ?? .secondary,
                title: "运行日志",
                subtitle: routerManager.status.subtitle,
                statusColor: routerManager.status.statusColor,
                isSelected: { if case .logs = selectedItem { return true }; return false }()
            )
            .tag(SettingsView.SidebarItem.logs)
        }
    }

    private func accountListRow(_ account: ProviderAccount) -> some View {
        accountRow(account)
            .tag(SettingsView.SidebarItem.account(account.id))
            .contextMenu {
                Button {
                    renameInput = account.displayName
                    pendingRenameAccount = account
                } label: { Label("重命名", systemImage: "pencil") }
                Button { ClipboardHelper.shared.copy(account.displayName) } label: { Label("复制账号名", systemImage: "doc.on.doc.fill") }
                Button { ClipboardHelper.shared.copy(account.providerID) } label: { Label("复制 Provider", systemImage: "doc.on.doc.fill") }
                Button { ClipboardHelper.shared.copy(account.id.uuidString) } label: { Label("复制账号 ID", systemImage: "doc.on.doc.fill") }
                if account.id != accountManager.activeAccountID {
                    Divider()
                    Button { selectAccountAndSync(id: account.id) } label: { Label("设为活跃账号", systemImage: "checkmark.circle.fill") }
                }
                Divider()
                Button(role: .destructive) { pendingDeleteAccount = account } label: { Label("删除账号", systemImage: "trash.fill") }
            }
    }

    private func codexConfigListRow(_ cfg: InjectionConfiguration) -> some View {
        codexConfigRow(cfg)
            .tag(SettingsView.SidebarItem.codexInjectionConfig(cfg.id))
            .contextMenu {
                Button { ClipboardHelper.shared.copy(cfg.label) } label: { Label("复制 label", systemImage: "doc.on.doc.fill") }
                Button { ClipboardHelper.shared.copy(cfg.providerID) } label: { Label("复制 Provider", systemImage: "doc.on.doc.fill") }
                Divider()
                Button { codexInjectionLayer.activateConfiguration(id: cfg.id) } label: { Label("激活", systemImage: "bolt.fill") }
                Divider()
                Button(role: .destructive) { pendingDeleteCodexConfig = cfg } label: { Label("删除", systemImage: "trash.fill") }
            }
    }

    private var accountsSectionHeader: some View {
        sidebarSectionHeader(title: "账号", systemImage: "person.2.fill") {
            addExpandedToggleButton(
                kind: .account,
                onExpand: { newAccountLabel = "新账号 \(shortNow())" },
                helpExpand: "新增账号",
                helpCollapse: "收起添加账号行"
            )
        }
    }

    private var accountsInlineAddRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                fieldLabel("名称")
                TextField("例如：我的 DeepSeek", text: $newAccountLabel)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("种类").frame(maxWidth: .infinity, alignment: .leading).font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6)
                ], spacing: 6) {
                    Button { commitAccountCreation(providerID: "freemodel", providerDisplayName: "FreeModel 网页") } label: {
                        Label("FreeModel 网页", systemImage: "globe").frame(maxWidth: .infinity)
                    }
                    Button { commitAccountCreation(providerID: "deepseek", providerDisplayName: "DeepSeek API") } label: {
                        Label("DeepSeek API", systemImage: "key.fill").frame(maxWidth: .infinity)
                    }
                    Button { commitAccountCreation(providerID: "openrouter", providerDisplayName: "OpenRouter API") } label: {
                        Label("OpenRouter API", systemImage: "arrow.triangle.branch").frame(maxWidth: .infinity)
                    }
                    Button { commitAccountCreation(providerID: "modelscope", providerDisplayName: "ModelScope API") } label: {
                        Label("ModelScope API", systemImage: "cube").frame(maxWidth: .infinity)
                    }
                }
            }
            HStack {
                Spacer()
                Button("取消") { addExpanded = nil }
            }
        }
        .font(.caption)
        .addRowPanel()
    }

    private var codexSectionHeader: some View {
        sidebarSectionHeader(title: "Codex 注入", systemImage: "key.horizontal.fill") {
            addExpandedToggleButton(
                kind: .codex,
                onExpand: {
                    newCodexLabel = "新配置 \(shortNow())"
                    newCodexProvider = "custom-\(shortNow())"
                },
                helpExpand: "添加一条新的注入配置",
                helpCollapse: "收起添加注入配置行"
            )
        }
    }

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
                        showToast("已添加：\(newCodexLabel) · 官方", at: $codexToast)
                    } label: {
                        Label("官方", systemImage: "person.crop.circle.badge.checkmark").frame(maxWidth: .infinity)
                    }
                    Button {
                        codexInjectionLayer.addEmptyThirdPartyConfiguration(label: newCodexLabel, providerID: newCodexProvider)
                        addExpanded = nil
                        if let newID = codexInjectionLayer.injectionConfigurations.last?.id {
                            selectedItem = .codexInjectionConfig(newID)
                        }
                        showToast("已添加：\(newCodexLabel) · 第三方", at: $codexToast)
                    } label: {
                        Label("第三方", systemImage: "square.and.pencil").frame(maxWidth: .infinity)
                    }
                }
            }
            HStack {
                Spacer()
                Button("取消") { addExpanded = nil }
            }
        }
        .font(.caption)
        .addRowPanel()
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

    private func codexConfigRow(_ cfg: InjectionConfiguration) -> some View {
        let isActive = (codexInjectionLayer.activeInjection?.configurationID == cfg.id)
        let isSelected: Bool = {
            if case .codexInjectionConfig(let selectedID) = selectedItem, selectedID == cfg.id { return true }
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

    private func isAccountSelected(_ id: UUID) -> Bool {
        if case .account(let selectedID) = selectedItem, selectedID == id { return true }
        return false
    }

    private func accountStatusText(_ account: ProviderAccount) -> String {
        let status: String
        switch account.queryMode {
        case .dashboard: status = account.hasDashboardSession ? "控制台已登录" : "控制台未登录"
        case .apiKey: status = account.hasAPIKey ? "已设 API Key" : "未设 API Key"
        }
        if let balance = account.lastBalance {
            return "\(balance.remainingFormatted) · \(status)"
        }
        return status
    }

    private func commitAccountCreation(providerID: String, providerDisplayName: String) {
        let account = accountManager.createAccount(displayName: newAccountLabel, providerID: providerID)
        selectAccountAndSync(id: account.id)
        addExpanded = nil
        showToast("已添加：\(account.displayName) · \(providerDisplayName)", at: $accountToast)
    }

    private func commitRename(input: String, accountID: UUID) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        accountManager.renameAccount(id: accountID, displayName: trimmed)
    }

    private func selectAccountAndSync(id: UUID) {
        accountManager.selectAccount(id: id)
        balanceManager.syncFromActiveAccount()
    }

    private func deleteAccountAndSync(id: UUID) {
        _ = accountManager.deleteAccount(id: id)
        balanceManager.syncFromActiveAccount()
        if case .account(let selID) = selectedItem, selID == id {
            selectedItem = nil
        }
    }

    private static func shortNow() -> String {
        let f = DateFormatter()
        f.dateFormat = "MMdd-HHmm"
        return f.string(from: Date())
    }

    private func shortNow() -> String { Self.shortNow() }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .frame(width: 56, alignment: .leading)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func addExpandedToggleButton(
        kind: AddKind,
        onExpand: @escaping () -> Void,
        helpExpand: String,
        helpCollapse: String
    ) -> some View {
        Button {
            addExpanded = (addExpanded == kind) ? nil : kind
            if addExpanded == kind { onExpand() }
        } label: {
            Image(systemName: addExpanded == kind ? "minus" : "plus")
        }
        .buttonStyle(.borderless)
        .help(addExpanded == kind ? helpCollapse : helpExpand)
    }

    private func sidebarSectionHeader<Trailing: View>(title: String, systemImage: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Label(title, systemImage: systemImage).font(.headline)
            Spacer()
            trailing()
        }
    }

    private func sidebarSectionHeader(title: String, systemImage: String) -> some View {
        sidebarSectionHeader(title: title, systemImage: systemImage) { EmptyView() }
    }

    private struct SidebarRow: View {
        let icon: String
        let iconColor: Color
        let title: String
        let subtitle: String?
        let statusColor: Color?
        let subtitleColor: Color
        var isSelected: Bool = false
        @State private var isHovered: Bool = false

        init(icon: String, iconColor: Color = .secondary, title: String, subtitle: String? = nil, statusColor: Color? = nil, subtitleColor: Color = .secondary, isSelected: Bool = false) {
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
                    Text(title).lineLimit(1)
                    if let subtitle {
                        Text(subtitle).font(.caption2).foregroundStyle(subtitleColor).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if let statusColor {
                    statusDot(color: statusColor, size: 7, help: "账号段：当前账号信息已配置")
                }
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 4).fill(backgroundFill))
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
        }

        private var backgroundFill: Color {
            if isSelected { return Color.accentFill }
            if isHovered  { return Color.secondary.opacity(0.10) }
            return Color.clear
        }
    }

    @State private var toastTask: Task<Void, Never>?

    private func showToast<T: Equatable>(_ value: T?, at binding: Binding<T?>, seconds: Double = 3.0) {
        toastTask?.cancel()
        withAnimation { binding.wrappedValue = value }
        guard value != nil else { return }
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            withAnimation { binding.wrappedValue = nil }
        }
    }
}
