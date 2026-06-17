//
//  CodeEditorView.swift
//  FreeModelMenuBar
//
//  代码编辑器 — 1:1 复用 logsConsoleSection 的"黑底 + 圆角 + 可选"形式。
//  logsConsoleSection 用的就是：ScrollView { LazyVStack { ... } }.background(Color.black).cornerRadius(6).textSelection(.enabled)
//  这里底层用 TextEditor 替代 LazyVStack（带内置滚动，所以去掉外层 ScrollView）。
//  关键：.background(Color.black) 必须直接挂到 TextEditor 自身，否则看不到黑底。
//

import SwiftUI

enum CodeLanguage: String {
    case json
    case toml
}

struct CodeEditorView: View {
    @Binding var text: String
    let language: CodeLanguage
    var minHeight: CGFloat = 200
    var idealHeight: CGFloat = 260
    var maxHeight: CGFloat = 320

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(.white)
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(minHeight: minHeight, idealHeight: idealHeight, maxHeight: maxHeight)
            .background(Color.black)        // 与 logsConsoleSection 一致
            .cornerRadius(6)                // 与 logsConsoleSection 一致
            .textSelection(.enabled)        // 与 logsConsoleSection 一致
    }
}
