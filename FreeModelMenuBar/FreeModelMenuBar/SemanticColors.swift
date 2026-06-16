//
//  SemanticColors.swift
//  FreeModelMenuBar
//
//  灰底透明度统一 token：4 档语义化（surface / surfaceElevated / accent / overlay）
//  P1-1 抽出：原 0.04/0.05/0.06/0.08/0.10/0.12/0.18/0.25 共 8 种值散落
//  4 档映射：
//    surface (0.06)          —— 内嵌字段/路由段浅灰底（最低视觉权重）
//    surfaceElevated (0.10)  —— 详情区 sectionPanel 灰底
//    accent (0.18)           —— 选中态/激活态背景（主色强调）
//    overlay (0.12)          —— 胶囊徽章 / 标签灰底
//  剩余 0.04/0.05/0.08/0.25 为单点特殊用途，保留原值
//

import SwiftUI

extension Color {
    /// 字段/路由段浅灰底（最低视觉权重）
    static let surfaceFill = Color.gray.opacity(0.06)
    /// 详情区 sectionPanel 灰底
    static let surfaceElevatedFill = Color.gray.opacity(0.10)
    /// 选中态/激活态背景（主色强调）
    static let accentFill = Color.accentColor.opacity(0.18)
    /// 胶囊徽章 / 标签灰底
    static let overlayFill = Color.gray.opacity(0.12)
}
