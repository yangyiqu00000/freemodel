//
//  ViewExtensions.swift
//  FreeModelMenuBar
//
//  跨文件 View extension（internal 级别，SettingsView 和 MenuContent 都能复用）
//  P2-16b 抽出：sectionDivider（详情区/菜单栏 6 处共用）
//

import SwiftUI

extension View {
    /// 详情区/菜单栏分段 Divider（4pt 垂直 padding），6 处共用
    func sectionDivider() -> some View {
        Divider().padding(.vertical, 4)
    }
}
