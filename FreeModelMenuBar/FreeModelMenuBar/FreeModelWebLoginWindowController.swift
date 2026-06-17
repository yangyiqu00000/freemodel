//
//  FreeModelWebLoginWindowController.swift
//  FreeModelMenuBar
//
//  内置网页登录窗口，用于取得 FreeModel 控制台会话。
//

import AppKit
import WebKit

@MainActor
final class FreeModelWebLoginWindowController: NSObject, NSWindowDelegate, WKNavigationDelegate {
    static let shared = FreeModelWebLoginWindowController()

    private var window: NSWindow?
    private var webView: WKWebView?
    private var syncTimer: Timer?
    private weak var balanceManager: BalanceManager?
    private weak var accountManager: AccountManager?
    private var loginAccountID: UUID?

    private override init() {
        super.init()
    }

    func openLogin(balanceManager: BalanceManager, accountManager: AccountManager) {
        self.balanceManager = balanceManager
        self.accountManager = accountManager
        self.loginAccountID = accountManager.activeAccount?.id

        let webView = makeWebView()
        let window: NSWindow

        if let existingWindow = self.window {
            window = existingWindow
            webView.removeFromSuperview()
            window.contentView = webView
        } else {
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 980, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "登录 FreeModel 控制台"
            window.center()
            window.delegate = self
            window.contentView = webView
            self.window = window
        }

        if let url = URL(string: "https://freemodel.dev/dashboard/usage") {
            webView.load(URLRequest(url: url))
        }

        startCookieSync()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        syncTimer?.invalidate()
        syncTimer = nil
        window = nil
        webView = nil
        loginAccountID = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        syncCookiesAndRefreshBalance()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        syncCookies()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        syncCookies()
    }

    private func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView
        return webView
    }

    private func startCookieSync() {
        syncTimer?.invalidate()
        // 类标了 @MainActor，Timer.scheduledTimer 也在主 runloop 上调度，闭包内直接调用即可，
        // 不需要再包一层 Task @MainActor。
        syncTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.syncCookies()
        }
    }

    private func syncCookiesAndRefreshBalance() {
        syncCookies { [weak self] hasFreeModelCookie in
            guard hasFreeModelCookie else { return }
            Task { @MainActor [weak self] in
                await self?.balanceManager?.fetchBalance()
            }
        }
    }

    private func syncCookies(completion: ((Bool) -> Void)? = nil) {
        let cookieStore = webView?.configuration.websiteDataStore.httpCookieStore ?? WKWebsiteDataStore.nonPersistent().httpCookieStore
        cookieStore.getAllCookies { cookies in
            let freeModelCookies = cookies.filter { $0.domain.contains("freemodel.dev") }
            Task { @MainActor [weak self] in
                guard let self, let accountID = self.loginAccountID else {
                    completion?(!freeModelCookies.isEmpty)
                    return
                }
                self.accountManager?.updateCookies(from: freeModelCookies, for: accountID)
                completion?(!freeModelCookies.isEmpty)
            }
        }
    }
}
