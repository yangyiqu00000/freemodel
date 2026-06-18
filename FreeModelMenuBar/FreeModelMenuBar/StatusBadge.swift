//
//  StatusBadge.swift
//  FreeModelMenuBar
//
//  统一的状态徽章组件：浅色背景 + 主色 icon/text
//  用于 API Key 状态、URL 预设反馈、Codex 注入激活/已自动保存、日志清除等"反馈型"徽章
//  注：MenuContent.router 状态灯（实色 + 白字 + 无 icon）形态不同，保留为独立实现
//
//  P2-10 抽出：4 个反馈型徽章（apiKeyStatus / urlPresetStatus / activeStatus / autoSavedBadge）
//  P3-32 补：logsClearedToast 也用 StatusBadge（trash.fill 灰色）
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
        HStack(spacing: Spacing.tight) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2)
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Spacing.standard)
        .padding(.vertical, Spacing.tight)
        .background(
            Capsule().fill(Color.overlayFill)
        )
        .frame(height: 22)
        .help(help ?? "")
    }
}
