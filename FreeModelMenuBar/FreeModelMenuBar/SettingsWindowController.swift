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
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "FreeModel 设置"
        newWindow.contentViewController = hostingController
        newWindow.isReleasedWhenClosed = false
        newWindow.level = .floating
        newWindow.minSize = NSSize(width: 640, height: 520)
        // 强制 light appearance —— 修复 Codex 注入页"全黑看不见"问题：
        // SwiftUI 嵌在 NSWindow 里时，详情区未设显式 background 会透出 NSWindow 底色；
        // dark mode 下底色近黑，导致整个详情区看上去全黑。锁 light 后浅灰底稳定可见。
        newWindow.appearance = NSAppearance(named: .aqua)
        // 同步给 hosting view 一个兜底底色（SwiftUI 内未设 background 的子视图会透出它）
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
