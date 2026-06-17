import SwiftUI

struct SettingsSidebarView: View {
    @Binding var selectedItem: SettingsView.SidebarItem?
    @ObservedObject var accountManager: AccountManager
    @ObservedObject var balanceManager: BalanceManager
    @ObservedObject var routerManager: RouterManager
    @ObservedObject var codexInjectionLayer: AppLayer
    @Binding var accountToast: String?
    @Binding var codexToast: String?
    @Binding var pendingDeleteCodexConfig: InjectionConfiguration?

    @State private var showAddAccount: Bool = false
    @State private var showAddCodexConfig: Bool = false
    @State private var pendingDeleteAccount: ProviderAccount?
    @State private var pendingRenameAccount: ProviderAccount?
    @State private var renameInput: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            List {
                accountsSection
                codexSection
                logsSection
            }
            .listStyle(.sidebar)
        }
        .sheet(isPresented: $showAddAccount) {
            AddAccountSheet(
                defaultLabel: "新账号 \(shortNow())",
                onPickProvider: { label, providerID, providerDisplayName in
                    showAddAccount = false
                    commitAccountCreation(label: label, providerID: providerID, providerDisplayName: providerDisplayName)
                },
                onCancel: { showAddAccount = false }
            )
        }
        .sheet(isPresented: $showAddCodexConfig) {
            AddCodexConfigSheet(
                defaultLabel: "新配置 \(shortNow())",
                defaultProviderID: "custom-\(shortNow())",
                onPickOfficial: { label in
                    showAddCodexConfig = false
                    commitCodexOfficialCreation(label: label)
                },
                onPickThirdParty: { label, providerID in
                    showAddCodexConfig = false
                    commitCodexThirdPartyCreation(label: label, providerID: providerID)
                },
                onCancel: { showAddCodexConfig = false }
            )
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
            ForEach(accountManager.accounts) { account in
                Button {
                    selectAccountAndSync(id: account.id)
                } label: {
                    accountRow(account)
                }
                .buttonStyle(.plain)
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
        }
    }

    private var codexSection: some View {
        Section(header: codexSectionHeader) {
            ForEach(codexInjectionLayer.injectionConfigurations) { cfg in
                Button {
                    selectedItem = .codexInjectionConfig(cfg.id)
                } label: {
                    codexConfigListRow(cfg)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var logsSection: some View {
        Section(header: sidebarSectionHeader(title: "运行日志", systemImage: "terminal.fill")) {
            Button {
                selectedItem = .logs
            } label: {
                SidebarRow(
                    icon: "terminal.fill",
                    iconColor: routerManager.status.statusColor ?? .secondary,
                    title: "运行日志",
                    subtitle: routerManager.status.subtitle,
                    statusColor: routerManager.status.statusColor,
                    isSelected: { if case .logs = selectedItem { return true }; return false }()
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func accountListRow(_ account: ProviderAccount) -> some View {
        accountRow(account)
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
            Button {
                showAddAccount = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("新增账号")
        }
    }

    private var codexSectionHeader: some View {
        sidebarSectionHeader(title: "Codex 注入", systemImage: "key.horizontal.fill") {
            Button {
                showAddCodexConfig = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("添加一条新的注入配置")
        }
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
        accountManager.activeAccountID == id
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

    private func commitAccountCreation(label: String, providerID: String, providerDisplayName: String) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalLabel = trimmed.isEmpty ? "新账号 \(shortNow())" : trimmed
        let account = accountManager.createAccount(displayName: finalLabel, providerID: providerID)
        selectAccountAndSync(id: account.id)
        showToast("已添加：\(account.displayName) · \(providerDisplayName)", at: $accountToast)
    }

    private func commitCodexOfficialCreation(label: String) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalLabel = trimmed.isEmpty ? "新配置 \(shortNow())" : trimmed
        codexInjectionLayer.prepareOfficialLoginSession(label: finalLabel)
        if let newID = codexInjectionLayer.injectionConfigurations.last?.id {
            selectedItem = .codexInjectionConfig(newID)
        }
        showToast("已添加：\(finalLabel) · 官方", at: $codexToast)
    }

    private func commitCodexThirdPartyCreation(label: String, providerID: String) {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedProvider = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalLabel = trimmedLabel.isEmpty ? "新配置 \(shortNow())" : trimmedLabel
        let finalProvider = trimmedProvider.isEmpty ? "custom-\(shortNow())" : trimmedProvider
        codexInjectionLayer.addEmptyThirdPartyConfiguration(label: finalLabel, providerID: finalProvider)
        if let newID = codexInjectionLayer.injectionConfigurations.last?.id {
            selectedItem = .codexInjectionConfig(newID)
        }
        showToast("已添加：\(finalLabel) · 第三方", at: $codexToast)
    }

    private func commitRename(input: String, accountID: UUID) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        accountManager.renameAccount(id: accountID, displayName: trimmed)
    }

    private func selectAccountAndSync(id: UUID) {
        accountManager.selectAccount(id: id)
        balanceManager.syncFromActiveAccount()
        selectedItem = .account(id)
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

// MARK: - AddAccountSheet

private struct AddAccountSheet: View {
    let defaultLabel: String
    let onPickProvider: (_ label: String, _ providerID: String, _ providerDisplayName: String) -> Void
    let onCancel: () -> Void

    @State private var label: String = ""
    @State private var labelDidInit: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                fieldLabel("名称")
                TextField("例如：我的 DeepSeek", text: $label)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submit)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("种类")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6)
                ], spacing: 6) {
                    Button { onPickProvider(label, "freemodel", "FreeModel 网页") } label: {
                        Label("FreeModel 网页", systemImage: "globe").frame(maxWidth: .infinity)
                    }
                    Button { onPickProvider(label, "deepseek", "DeepSeek API") } label: {
                        Label("DeepSeek API", systemImage: "key.fill").frame(maxWidth: .infinity)
                    }
                    Button { onPickProvider(label, "openrouter", "OpenRouter API") } label: {
                        Label("OpenRouter API", systemImage: "arrow.triangle.branch").frame(maxWidth: .infinity)
                    }
                    Button { onPickProvider(label, "modelscope", "ModelScope API") } label: {
                        Label("ModelScope API", systemImage: "cube").frame(maxWidth: .infinity)
                    }
                }
            }

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .font(.caption)
        .padding(16)
        .frame(width: 360)
        .onAppear {
            if !labelDidInit {
                label = defaultLabel
                labelDidInit = true
            }
        }
    }

    private func submit() {
        // chip 按钮直接触发 onPickProvider；此函数保留以支持 TextField 回车（目前无选择时不创建）
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .frame(width: 56, alignment: .leading)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

// MARK: - AddCodexConfigSheet

private struct AddCodexConfigSheet: View {
    let defaultLabel: String
    let defaultProviderID: String
    let onPickOfficial: (_ label: String) -> Void
    let onPickThirdParty: (_ label: String, _ providerID: String) -> Void
    let onCancel: () -> Void

    @State private var label: String = ""
    @State private var providerID: String = ""
    @State private var didInit: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                fieldLabel("标签")
                TextField("例如：本地 relay", text: $label)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                fieldLabel("Provider")
                TextField("例如：local-relay", text: $providerID)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("种类")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6)
                ], spacing: 6) {
                    Button {
                        onPickOfficial(label)
                    } label: {
                        Label("官方", systemImage: "person.crop.circle.badge.checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    Button {
                        onPickThirdParty(label, providerID)
                    } label: {
                        Label("第三方", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .font(.caption)
        .padding(16)
        .frame(width: 360)
        .onAppear {
            if !didInit {
                label = defaultLabel
                providerID = defaultProviderID
                didInit = true
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .frame(width: 64, alignment: .leading)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
