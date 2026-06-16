//
//  StatusBadge.swift
//  FreeModelMenuBar
//
//  统一的状态徽章组件：浅色背景 + 主色 icon/text
//  用于 API Key 状态、URL 预设反馈、Codex 注入激活/已自动保存等"反馈型"徽章
//  注：Router 状态灯（实色 + 白字 + 无 icon）形态不同，保留为独立实现
//

import SwiftUI

struct StatusBadge: View {
    enum Style {
        case subtle   // 浅色 capsule 背景 + 主色文字（默认）
    }

    let icon: String
    let text: String
    let tint: Color
    var style: Style = .subtle
    var help: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2)
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(tint.opacity(0.12))
        )
        .frame(height: 22)
        .help(help ?? "")
    }
}
