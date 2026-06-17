//
//  FreeModelMenuBarApp.swift
//  FreeModelMenuBar
//
//  macOS 菜单栏应用 - 实时监控 FreeModel 账户余额
//

import SwiftUI

@main
struct FreeModelMenuBarApp: App {
    @StateObject private var accountManager: AccountManager
    @StateObject private var balanceManager: BalanceManager
    @StateObject private var routerManager: RouterManager

    init() {
        let accountManager = AccountManager()
        let balanceManager = BalanceManager(accountManager: accountManager)
        let routerManager = RouterManager(accountManager: accountManager)
        
        _accountManager = StateObject(wrappedValue: accountManager)
        _balanceManager = StateObject(wrappedValue: balanceManager)
        _routerManager = StateObject(wrappedValue: routerManager)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(accountManager)
                .environmentObject(balanceManager)
                .environmentObject(routerManager)
        } label: {
            Label {
                Text("FreeModel")
            } icon: {
                Image(systemName: balanceManager.isLoading ? "arrow.triangle.2.circlepath" : "dollarsign.circle.fill")
                    .loadingPulse(isActive: balanceManager.isLoading)
            }
            .onAppear {
                // 如果未配置账号，在应用启动时自动打开设置界面，避免用户因没有窗口误以为程序打不开
                if !balanceManager.isConfigured {
                    SettingsWindowController.shared.openSettings(
                        balanceManager: balanceManager,
                        accountManager: accountManager,
                        routerManager: routerManager
                    )
                }
            }
        }
        .menuBarExtraStyle(.window)

        // 注意：不使用 Settings scene，因为 LSUIElement (Agent 模式) 下它无法正常工作
        // 设置窗口通过 SettingsWindowController 手动管理
    }
}

private extension View {
    @ViewBuilder
    func loadingPulse(isActive: Bool) -> some View {
        if #available(macOS 14.0, *) {
            self.symbolEffect(.pulse, options: .repeating, isActive: isActive)
        } else {
            self
        }
    }
}
