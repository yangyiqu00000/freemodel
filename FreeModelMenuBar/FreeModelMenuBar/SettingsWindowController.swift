//
//  SettingsWindowController.swift
//  FreeModelMenuBar
//
//  手动管理设置窗口 - 解决 LSUIElement (Agent 模式) 下 Settings scene 无法打开的问题
//

import SwiftUI
import AppKit

/// 设置窗口的 NSWindowController 子类。
/// 使用标准 NSWindowController 生命周期：windowDidLoad 是 Apple 文档明确推荐
/// 的"窗口首次出现定位"钩子，在此处调 center() 让窗口从第一帧就落在屏幕正中。
/// 设置窗口尺寸 token（SettingsView 与 SettingsWindowController 共用——避免 720×620 散落两处）
enum WindowMetrics {
    /// 设置窗口默认尺寸
    static let defaultSize = CGSize(width: 720, height: 620)
}

@MainActor
final class SettingsNSWindowController: NSWindowController, NSWindowDelegate {
    convenience init(rootView: AnyView) {
        let hosting = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: WindowMetrics.defaultSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.title = "设置"
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.minSize = NSSize(width: 640, height: 520)
        window.setFrameAutosaveName("")
        hosting.view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        hosting.view.wantsLayer = true
        self.init(window: window)
        window.delegate = self
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        // 标准做法：Apple 文档推荐的"窗口首次出现定位"钩子。
        // center() 内部使用 NSScreen.main.visibleFrame 的中点（已正确排除 menu bar 与 Dock），
        // 不需要手算 origin。NSWindowController 走完 windowDidLoad 后才会 orderFront，
        // 因此窗口第一帧就显示在屏幕正中，不会出现"先在 (0,0) 出现再被居中"的双阶段跳变。
        window?.center()
    }

    func windowWillClose(_ notification: Notification) {
        // 通知 holder 释放引用（避免窗口被关闭后控制器还持有 NSWindow）
        NotificationCenter.default.post(name: .settingsWindowDidClose, object: nil)
    }
}

extension Notification.Name {
    static let settingsWindowDidClose = Notification.Name("com.freemodel.settingsWindowDidClose")
}

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var controller: SettingsNSWindowController?

    private init() {
        NotificationCenter.default.addObserver(
            forName: .settingsWindowDidClose,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.controller = nil
            }
        }
    }

    /// 打开或激活设置窗口
    func openSettings(balanceManager: BalanceManager, accountManager: AccountManager, routerManager: RouterManager) {
        if let existing = controller, existing.window?.isVisible == true {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
            .environmentObject(accountManager)
            .environmentObject(balanceManager)
            .environmentObject(routerManager)

        let new = SettingsNSWindowController(rootView: AnyView(settingsView))
        // showWindow 触发 windowDidLoad（center 发生在这里），然后 makeKeyAndOrderFront
        // 在下一轮主循环把窗口推到屏幕上——此时 frame 已经在屏幕正中。
        new.showWindow(nil)
        new.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.controller = new
    }

    /// 关闭设置窗口
    func closeSettings() {
        controller?.close()
        controller = nil
    }
}
