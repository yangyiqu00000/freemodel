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

    /// Toast 反馈徽章（4 处共用：accountCreated / codexConfigCreated / baseURLCopied / logsCleared）
    /// - value: Optional String 状态（nil 不渲染）
    /// - icon / tint: 徽章主色与 icon
    /// 统一模板：if let + StatusBadge + .transition(.opacity)
    @ViewBuilder
    func toastBadge(value: String?, icon: String, tint: Color) -> some View {
        if let text = value {
            StatusBadge(icon: icon, text: text, tint: tint)
                .transition(.opacity)
        }
    }

    /// 状态指示圆点（size: 6/7/8，4 处共用，保留 3 种 size 表视觉层次：侧栏小 6 / dashboard 中 7 / 段 header 大 8）
    /// - help: 可选 hover 提示文字（账号 / 路由 / Codex 状态说明）
    func statusDot(color: Color, size: CGFloat = 6, help: String? = nil) -> some View {
        let dot = Circle()
            .fill(color)
            .frame(width: size, height: size)
        if let help {
            return AnyView(dot.help(help))
        } else {
            return AnyView(dot)
        }
    }

    /// 详情区段背景（gray 8pt 圆角 panel）——8 处统一使用
    func sectionPanel() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.surfaceElevatedFill))
    }

    /// 详情区 3 段内部 VStack（与 sectionPanel 内部 padding 16 对齐）
    func sectionVStack<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16, content: content)
    }

    /// 侧边栏内联添加行背景（blue 6pt 圆角小卡片）——2 处统一使用（账号 + Codex 注入）
    func addRowPanel() -> some View {
        self
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.blue.opacity(0.08))
            )
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
