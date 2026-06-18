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
        Divider().padding(.vertical, Spacing.tight)
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
        VStack(alignment: .leading, spacing: Spacing.loose, content: content)
    }

    /// 侧边栏内联添加行背景（blue 6pt 圆角小卡片）——2 处统一使用（账号 + Codex 注入）
    func addRowPanel() -> some View {
        self
            .padding(Spacing.standard)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.blue.opacity(0.08))
            )
    }

    /// 详情区/日志按钮统一高度 28pt（替代散落的 .frame(height: 28)）——10 处共用
    /// 默认 28pt；后续要全局调整按钮高度只改这里即可
    func uniformButtonHeight(_ height: CGFloat = 28) -> some View {
        self.frame(height: height)
    }

    /// 导航区 Header（设置窗口标题 + 日志段标题共用）
    func navHeader(icon: String, tint: Color, title: String, subtitle: String, dotColor: Color? = nil) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                HStack(spacing: 6) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let color = dotColor {
                        statusDot(color: color, help: "路由代理状态")
                    }
                }
            }
        }
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

// MARK: - 滑动条覆盖样式（NSView 桥接）

struct OverlayScrollerModifier: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.alphaValue = 0
        DispatchQueue.main.async {
            var current = view.superview
            while current != nil {
                if let scrollView = current as? NSScrollView {
                    scrollView.scrollerStyle = .overlay
                    scrollView.scrollerKnobStyle = .default
                    break
                }
                current = current?.superview
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    /// 覆盖式滑动条：无 track 背景、仅滚动时浮现滑块
    func overlayScrollers() -> some View {
        self.background(OverlayScrollerModifier())
    }
}
//
//  AppTypography.swift
//  FreeModelMenuBar
//
//  跨文件字号尺度（与 SemanticColors.swift 同级）。
//  6 档 enum 替代散落在 3 个文件里的 14 处 .font(.system(size: ...))
//  写死值，让"字号协调"有一个明确的参照系。
//
//  调 appFontScale 可一次性缩放所有 AppFont（仅影响 Font.appXxx 调用点，
//  不影响 .headline / .caption / 等 SwiftUI 语义字体）
//


/// 全局字号缩放系数。默认 1.0；要"全局 +20%" 改 1.2 即可。
let appFontScale: CGFloat = 1.0
/// 全局 spacing 尺度（5 档语义 token）
/// - tight (4): 紧凑排版（如 HStack 内 icon + text 紧贴）
/// - standard (8): 标准间距（最常用，VStack/HStack 段内）
/// - relaxed (12): 段间呼吸（详情区子段）
/// - loose (16): 大段间隔（详情区 section 之间）
/// - section (24): 详情区外圈 padding
/// 其余 2/6/10/14/18/20 为单点特殊用途，保留原值
enum Spacing {
    static let tight: CGFloat = 4
    static let standard: CGFloat = 8
    static let relaxed: CGFloat = 12
    static let loose: CGFloat = 16
    static let section: CGFloat = 24
}


/// 应用字号档位（6 档：4 类小字号 + 1 档大数字）
enum AppFont {
    /// 9pt bold 徽章（菜单栏顶栏小标签）
    case microLabel
    /// 9-10pt 小说明文字（含 monospaced 变体）
    case microTag
    /// 12pt monospaced 编辑器正文
    case editorBody
    /// 10pt monospaced 日志行
    case logMono
    /// 14pt 侧栏小图标
    case sidebarIcon
    /// 32pt bold rounded 大数字展示
    case displayNumber
}

extension Font {
    /// 按 appFontScale 渲染的 AppFont
    static func app(_ kind: AppFont) -> Font {
        let base: Font
        switch kind {
        case .microLabel:
            base = .system(size: 9 * appFontScale, weight: .bold, design: .default)
        case .microTag:
            base = .system(size: 10 * appFontScale, weight: .regular, design: .default)
        case .editorBody:
            base = .system(size: 12 * appFontScale, weight: .regular, design: .monospaced)
        case .logMono:
            base = .system(size: 10 * appFontScale, weight: .regular, design: .monospaced)
        case .sidebarIcon:
            base = .system(size: 14 * appFontScale, weight: .regular, design: .default)
        case .displayNumber:
            base = .system(size: 32 * appFontScale, weight: .bold, design: .rounded)
        }
        return base
    }
}

// MARK: - Toast 自动消失任务（3 处 view 共用：SettingsView / LogsConsoleView / SettingsSidebarView）
//
// 旧 toast 会被新 toast 取消（防过期复活），value=nil 不会启动计时器。
// 接受 Binding<T?> 写入值；用 @MainActor 隔离避免跨线程更新 binding。
@discardableResult
func scheduleToastDismiss<T: Equatable>(
    value: T?,
    binding: Binding<T?>,
    seconds: Double = 3.0
) -> Task<Void, Never>? {
    withAnimation { binding.wrappedValue = value }
    guard value != nil else { return nil }
    return Task { @MainActor in
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        guard !Task.isCancelled else { return }
        withAnimation { binding.wrappedValue = nil }
    }
}
