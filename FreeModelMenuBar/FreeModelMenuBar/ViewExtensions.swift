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

    /// 状态指示圆点（size: 6/7/8，4 处共用，保留 3 种 size 表视觉层次：侧栏小 6 / dashboard 中 7 / 段 header 大 8）
    func statusDot(color: Color, size: CGFloat = 6) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}

extension Binding where Value == Bool {
    /// Optional State → Bool Binding（get: nil? false ; set: true → 不变, false → 置 nil），3 处共用
    /// 用于 alert/.confirmationDialog 的 isPresented 绑定 optional 状态
    static func nilify<T>(_ state: Binding<T?>) -> Binding<Bool> {
        Binding<Bool>(
            get: { state.wrappedValue != nil },
            set: { if !$0 { state.wrappedValue = nil } }
        )
    }
}
