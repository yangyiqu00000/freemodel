//
//  ClipboardHelper.swift
//  FreeModelMenuBar
//
//  统一剪贴板复制入口：clearContents + setString 同一来源
//  P2-13 抽出：原 13 处 NSPasteboard 散落（SettingsView 12 + MenuContent 1）
//

import AppKit

final class ClipboardHelper {
    static let shared = ClipboardHelper()
    private init() {}

    func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
