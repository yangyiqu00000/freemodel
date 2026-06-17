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
                            if accountManager.accounts.contains(where: { $0.id == accountID }) {
                                AccountSettingsView(
                                    accountID: accountID,
                                    accountManager: accountManager,
                                    balanceManager: balanceManager,
                                    routerManager: routerManager,
                                    pendingScrollToAPIKey: $pendingScrollToAPIKey
                                )
                                .id(accountID)
                            } else {
                                emptyStateView(.accountGone)
                            }
                        case .codexInjectionConfig(let cfgID):
                            CodexInjectionSettingsView(
                                appLayer: codexInjectionLayer,
                                configurationID: cfgID,
                                pendingDeleteCodexConfig: $pendingDeleteCodexConfig
                            )
                        case .logs:
                            LogsConsoleView(
                                routerManager: routerManager,
                                accountManager: accountManager
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
            balanceManager.syncFromActiveAccount()
        }
    }

    // MARK: - 侧边栏已提取至 SettingsSidebarView.swift

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
                    .font(.app(.displayNumber))
                    .foregroundStyle(.orange)
                Text("还没有选中账号")
                    .font(.headline)
                Text("点击侧边栏右上角的 + 添加账号，或选中现有账号")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case .accountGone:
                Image(systemName: "questionmark.circle")
                    .font(.app(.displayNumber))
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

}

// sectionPanel / sectionVStack / addRowPanel 已移至 ViewExtensions.swift
