//
//  CodeEditorView.swift
//  FreeModelMenuBar
//
//  代码编辑器 — logsConsoleSection 同款样式（黑底 + 圆角 + 可选），背景色跟随系统外观自适应。
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
            .font(.app(.editorBody))
            .foregroundStyle(.white)
            .scrollContentBackground(.hidden)
            .padding(Spacing.standard)
            .frame(minHeight: minHeight, idealHeight: idealHeight, maxHeight: maxHeight)
            .background(Color.codeBackground)
            .cornerRadius(6)
            .textSelection(.enabled)
    }
}
