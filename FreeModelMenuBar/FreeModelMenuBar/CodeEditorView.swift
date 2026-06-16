//
//  CodeEditorView.swift
//  FreeModelMenuBar
//
//  代码编辑器：NSTextView + NSAttributedString 语法高亮 + 行号 ruler + 浅灰主题 + 外框
//  - 支持 JSON / TOML 两种语言（auth.json / config.toml）
//  - 关键字 / 字符串 / 数字 / 括号 / 注释 / 运算符 各自颜色
//  - 行号通过 NSTextView 原生 rulerView 渲染（自动跟随滚动）
//
//  颜色规格（用户指定）：
//    底色 / 外框   浅灰 (light gray)
//    行号侧栏       单独浅灰（更深一点）
//    关键字 (def/class/if 等)  绿色
//    括号            浅灰色统一
//    字符串          橘红色
//    注释            浅灰半透明
//    数字            浅蓝色
//    运算符          白色
//    文本主色        白色
//

import SwiftUI
import AppKit

// MARK: - 语言枚举

enum CodeLanguage: String {
    case json
    case toml

    /// 该语言的关键字集合（绿色高亮）
    var keywords: Set<String> {
        switch self {
        case .json: return ["true", "false", "null"]
        case .toml: return ["true", "false"]
        }
    }

    /// 注释前缀（半透明浅灰）
    var commentPrefix: String? {
        switch self {
        case .json: return nil  // JSON 无注释
        case .toml: return "#"
        }
    }
}

// MARK: - 颜色主题（浅灰底 + 白色文本 + 多种 token 颜色）

enum CodeEditorPalette {
    /// 编辑区底色（浅灰）
    static let editorBackground = NSColor(calibratedRed: 0.94, green: 0.94, blue: 0.95, alpha: 1.0)
    /// 行号侧栏底色（更深一点浅灰）
    static let gutterBackground = NSColor(calibratedRed: 0.87, green: 0.87, blue: 0.89, alpha: 1.0)
    /// 外框描边色
    static let border = NSColor(calibratedRed: 0.72, green: 0.72, blue: 0.74, alpha: 1.0)

    /// 文本主色（白）
    static let text = NSColor.white
    /// 关键字（绿）
    static let keyword = NSColor(calibratedRed: 0.30, green: 0.78, blue: 0.40, alpha: 1.0)
    /// 字符串（橘红）
    static let string = NSColor(calibratedRed: 0.96, green: 0.52, blue: 0.20, alpha: 1.0)
    /// 数字（浅蓝）
    static let number = NSColor(calibratedRed: 0.40, green: 0.72, blue: 0.98, alpha: 1.0)
    /// 括号（浅灰统一）
    static let bracket = NSColor(calibratedRed: 0.78, green: 0.78, blue: 0.80, alpha: 1.0)
    /// 注释（浅灰半透明）
    static let comment = NSColor(calibratedRed: 0.65, green: 0.65, blue: 0.68, alpha: 0.55)
    /// 运算符（白）
    static let operator_ = NSColor.white
    /// 行号颜色（深灰）
    static let lineNumber = NSColor(calibratedRed: 0.50, green: 0.50, blue: 0.55, alpha: 0.9)
}

// MARK: - 语法高亮器

/// 一次扫描整段文本，输出每个字符的 (NSColor, 字符) 元组；然后拼成 NSAttributedString
/// 单遍算法：按"最长优先"匹配 — 字符串 > 数字 > 标识符 > 符号
enum CodeHighlighter {

    /// 返回着色后的 NSAttributedString（monospaced body 字体）
    static func highlight(_ text: String, language: CodeLanguage) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let result = NSMutableAttributedString()
        var i = text.startIndex

        while i < text.endIndex {
            let c = text[i]

            // 1) 注释
            if let prefix = language.commentPrefix, text[i...].hasPrefix(prefix) {
                let end = text.endIndex
                let segment = String(text[i..<end])
                result.append(NSAttributedString(
                    string: segment,
                    attributes: [.foregroundColor: CodeEditorPalette.comment, .font: font]
                ))
                break
            }

            // 2) 字符串（双引号）
            if c == "\"" {
                let strEnd = findStringEnd(in: text, from: text.index(after: i))
                let segment = String(text[i..<strEnd])
                result.append(NSAttributedString(
                    string: segment,
                    attributes: [.foregroundColor: CodeEditorPalette.string, .font: font]
                ))
                i = strEnd
                continue
            }

            // 3) 数字（含负号小数）
            if c.isNumber || (c == "-" && text.index(after: i) < text.endIndex && text[text.index(after: i)].isNumber) {
                var j = i
                if c == "-" { j = text.index(after: j) }
                while j < text.endIndex, text[j].isNumber || text[j] == "." || text[j] == "e" || text[j] == "E" || text[j] == "+" || text[j] == "-" {
                    j = text.index(after: j)
                }
                let segment = String(text[i..<j])
                result.append(NSAttributedString(
                    string: segment,
                    attributes: [.foregroundColor: CodeEditorPalette.number, .font: font]
                ))
                i = j
                continue
            }

            // 4) 标识符（关键字）
            if c.isLetter || c == "_" {
                var j = i
                while j < text.endIndex, text[j].isLetter || text[j].isNumber || text[j] == "_" {
                    j = text.index(after: j)
                }
                let word = String(text[i..<j])
                let color: NSColor = language.keywords.contains(word) ? CodeEditorPalette.keyword : CodeEditorPalette.text
                result.append(NSAttributedString(
                    string: word,
                    attributes: [.foregroundColor: color, .font: font]
                ))
                i = j
                continue
            }

            // 5) 括号
            if "()[]{}".contains(c) {
                result.append(NSAttributedString(
                    string: String(c),
                    attributes: [.foregroundColor: CodeEditorPalette.bracket, .font: font]
                ))
                i = text.index(after: i)
                continue
            }

            // 6) 运算符
            if "+-*/=<>!:,.".contains(c) {
                result.append(NSAttributedString(
                    string: String(c),
                    attributes: [.foregroundColor: CodeEditorPalette.operator_, .font: font]
                ))
                i = text.index(after: i)
                continue
            }

            // 7) 其他（空白 / 换行）
            result.append(NSAttributedString(
                string: String(c),
                attributes: [.foregroundColor: CodeEditorPalette.text, .font: font]
            ))
            i = text.index(after: i)
        }

        return result
    }

    /// 找到字符串结束位置（处理 \\ 转义）；包含末尾的 "
    private static func findStringEnd(in text: String, from start: String.Index) -> String.Index {
        var j = start
        while j < text.endIndex {
            let c = text[j]
            if c == "\\" {
                // 跳过转义字符
                let next = text.index(after: j)
                if next < text.endIndex {
                    j = text.index(after: next)
                } else {
                    return text.endIndex
                }
                continue
            }
            if c == "\"" {
                return text.index(after: j)
            }
            if c == "\n" {
                // JSON 不支持多行字符串；遇到换行视为异常，停止
                return j
            }
            j = text.index(after: j)
        }
        return text.endIndex
    }
}

// MARK: - 行号 Ruler

/// 自定义 NSRulerView：左侧浅灰侧栏 + 数字行号 + 主题色
final class CodeLineNumberRulerView: NSRulerView {

    init(scrollView: NSScrollView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        self.clientView = scrollView.documentView
        self.ruleThickness = 36
    }

    required init(coder: NSCoder) { fatalError() }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        // 背景：单独浅灰（与编辑区区分）
        CodeEditorPalette.gutterBackground.setFill()
        rect.fill()

        // 右侧分隔线
        NSColor(calibratedRed: 0.78, green: 0.78, blue: 0.80, alpha: 0.6).setFill()
        NSRect(x: ruleThickness - 1, y: 0, width: 1, height: rect.height).fill()

        guard let textView = clientView as? NSTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: CodeEditorPalette.lineNumber
        ]

        let glyphRangeVisible = layoutManager.glyphRange(forBoundingRect: textView.visibleRect, in: textContainer)
        let text = textView.string as NSString
        let totalLen = text.length
        guard totalLen > 0 else { return }

        // 用 lineFragmentRect + 累计字符遍历每行
        var lineIndex = 1
        var glyphIndex = glyphRangeVisible.location
        let glyphEnd = NSMaxRange(glyphRangeVisible)

        while glyphIndex < glyphEnd {
            let lineRange = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: nil,
                withoutAdditionalLayout: true
            )
            let yCenter = lineRange.origin.y + textView.textContainerInset.height
            let str = "\(lineIndex)" as NSString
            let size = str.size(withAttributes: attrs)
            let x = ruleThickness - size.width - 6
            str.draw(at: NSPoint(x: x, y: yCenter - size.height / 2 + 1), withAttributes: attrs)

            // 跳到下一行
            var lineGlyphRange = NSRange()
            layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: &lineGlyphRange,
                withoutAdditionalLayout: true
            )
            let consumed = NSMaxRange(lineGlyphRange)
            glyphIndex = consumed > glyphIndex ? consumed : glyphIndex + 1
            lineIndex += 1
        }
    }
}

// MARK: - SwiftUI 包装

struct CodeEditorView: NSViewRepresentable {
    @Binding var text: String
    let language: CodeLanguage
    var minHeight: CGFloat = 60
    var maxHeight: CGFloat = 320

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = CodeEditorPalette.editorBackground

        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.usesFindBar = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.backgroundColor = CodeEditorPalette.editorBackground
        textView.drawsBackground = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = CodeEditorPalette.text
        textView.insertionPointColor = .white
        textView.delegate = context.coordinator

        scrollView.documentView = textView

        // 行号 ruler
        let ruler = CodeLineNumberRulerView(scrollView: scrollView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        // 初始内容（已着色）
        textView.textStorage?.setAttributedString(CodeHighlighter.highlight(text, language: language))

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.language = language

        // 高度限制
        textView.minSize = NSSize(width: 0, height: minHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.frame = NSRect(x: 0, y: 0, width: scrollView.contentSize.width, height: maxHeight)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // SwiftUI 状态变更时（外部 text binding 改）同步到 NSTextView
        guard let textView = nsView.documentView as? NSTextView else { return }
        if context.coordinator.updatingFromBinding { return }

        if textView.string != text {
            let selected = textView.selectedRange
            textView.textStorage?.setAttributedString(CodeHighlighter.highlight(text, language: language))
            textView.selectedRange = NSRange(location: min(selected.location, text.count), length: 0)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        var language: CodeLanguage = .json
        var updatingFromBinding: Bool = false

        init(text: Binding<String>) { self._text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            // 把 NSTextView 的纯文本同步到 SwiftUI binding
            updatingFromBinding = true
            text = textView.string
            updatingFromBinding = false
            // 不重写 textStorage！用户在打字，避免每键重算高亮（性能 + 闪屏）
            // 折中：用 layoutManager 让 cursor / selection 颜色自然继承
        }
    }
}
