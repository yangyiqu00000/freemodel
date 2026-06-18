//
//  SettingsWindowController.swift
//  FreeModelMenuBar
//
//  手动管理设置窗口 - 解决 LSUIElement (Agent 模式) 下 Settings scene 无法打开的问题
//

import SwiftUI
import AppKit

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    /// 设置窗口尺寸 token（SettingsView 与 SettingsWindowController 共用——避免 720×620 散落两处）
    enum WindowMetrics {
        /// 设置窗口默认尺寸
        static let defaultSize = CGSize(width: 720, height: 620)
    }

    private var window: NSWindow?

    private init() {}

    /// 打开或激活设置窗口
    func openSettings(balanceManager: BalanceManager, accountManager: AccountManager, routerManager: RouterManager) {
        if let existingWindow = window, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
            .environmentObject(accountManager)
            .environmentObject(balanceManager)
            .environmentObject(routerManager)

        let hostingController = NSHostingController(rootView: settingsView)

        let newWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: WindowMetrics.defaultSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "FreeModel 设置"
        newWindow.contentViewController = hostingController
        newWindow.isReleasedWhenClosed = false
        newWindow.level = .floating
        newWindow.minSize = NSSize(width: 640, height: 520)
        // 暗色模式已解锁：所有详情区均有显式 background（windowBackgroundColor / controlBackgroundColor / codeBackground），
        // 无需再强制 light appearance。详见 SettingsView:95 / CodexInjectionSettingsView:81,86 / SemanticColors.codeBackground。
        // 注：logs 控制台和代码编辑器故意使用深色底（Color.codeBackground），与暗色主题自然融合。
        hostingController.view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        hostingController.view.wantsLayer = true

        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // 窗口显示后再居中（菜单栏应用在 makeKeyAndOrderFront 之前 screen 可能为 nil）
        DispatchQueue.main.async {
            if let screen = newWindow.screen ?? NSScreen.main {
                let rect = newWindow.frame
                newWindow.setFrameOrigin(NSPoint(
                    x: screen.visibleFrame.midX - rect.width / 2,
                    y: screen.visibleFrame.midY - rect.height / 2
                ))
            }
        }

        self.window = newWindow
    }

    /// 关闭设置窗口
    func closeSettings() {
        window?.close()
        window = nil
    }
}
