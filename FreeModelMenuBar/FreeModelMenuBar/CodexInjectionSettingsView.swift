//
//  CodexInjectionSettingsView.swift
//  FreeModelMenuBar
//
//  单条注入配置的"详情区"。由 SettingsView 在右侧主区域渲染。
//  不再有 sheet / popover / DisclosureGroup / swipeActions。
//  顶部：标签 + Provider 两个文本框；右上角绿色「激活」/ 灰底「已激活 ✓」按钮。
//  中间：auth.json + config.toml 两个自适应高度编辑框（官方配置在 auth.json 上方提供抓取链接）。
//  底部：「恢复默认」按钮：清空 ~/.codex/auth.json + config.toml，回到初始 Codex 状态。
//

import SwiftUI

struct CodexInjectionSettingsView: View {
    @ObservedObject var appLayer: AppLayer
    let configurationID: String
    @Binding var pendingDeleteCodexConfig: InjectionConfiguration?

    // 进入详情页时的"创建时" label / providerID（用于 undo 按钮）
    @State private var initialLabel: String = ""
    @State private var initialProviderID: String = ""
    @State private var didCaptureInitial: Bool = false

    // "已自动保存" 反馈：用户改任意字段立即更新，下次变更覆盖
    @State private var autoSavedAt: Date? = nil

    var body: some View {
        if let cfg = currentConfig {
            VStack(alignment: .leading, spacing: 16) {
                header(cfg)
                Divider()
                labelsAndProvider(cfg)
                editors(cfg)
                bottomActions(cfg)
            }
            .padding(20)
            .task { await appLayer.refresh() }
            .onAppear {
                if !didCaptureInitial {
                    initialLabel = cfg.label
                    initialProviderID = cfg.providerID
                    didCaptureInitial = true
                }
            }
            .onChange(of: cfg.label) { _ in triggerAutoSaveToast() }
            .onChange(of: cfg.providerID) { _ in triggerAutoSaveToast() }
            .onChange(of: cfg.authJSON) { _ in triggerAutoSaveToast() }
            .onChange(of: cfg.configTOML) { _ in triggerAutoSaveToast() }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "questionmark.circle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("该注入配置已不存在。")
                    .foregroundStyle(.secondary)
                Button("关闭") { /* 父层负责清 selectedItem */ }
                    .disabled(true)
            }
            .padding(20)
        }
    }

    private var currentConfig: InjectionConfiguration? {
        appLayer.injectionConfigurations.first(where: { $0.id == configurationID })
    }

    // MARK: - 头部

    private func header(_ cfg: InjectionConfiguration) -> some View {
        HStack {
            Image(systemName: "key.horizontal.fill")
                .font(.title2)
                .foregroundStyle(.blue)
            Text("Codex 注入").font(.title2).fontWeight(.bold)
            Text("·").foregroundStyle(.secondary)
            Text(cfg.label).font(.title3).foregroundStyle(.secondary)
            Spacer()
            activeStatusBadge(cfg)
            if let savedAt = autoSavedAt {
                Spacer().frame(width: 8)
                autoSavedBadge(at: savedAt)
            }
        }
    }

    @ViewBuilder
    private func activeStatusBadge(_ cfg: InjectionConfiguration) -> some View {
        let isActive = (appLayer.activeInjection?.configurationID == cfg.id)
        if isActive, let activatedAt = appLayer.activeInjection?.activatedAt {
            // 激活态：显示激活时间，让用户看到"激活多久了"——比单字"已激活"信息密度高
            HStack(spacing: 6) {
                StatusBadge(icon: "checkmark.circle.fill", text: "已激活", tint: .green)
                Text("·").foregroundStyle(.secondary)
                Text(activatedAt, style: .time)
            }
            .font(.caption)
            .help("激活于 \(activatedAt.formatted(date: .abbreviated, time: .standard))")
        } else {
            StatusBadge(icon: "circle.dashed", text: "未激活", tint: .secondary)
        }
    }

    private func labelsAndProvider(_ cfg: InjectionConfiguration) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text("标签").font(.caption).foregroundStyle(.secondary)
                    if cfg.label != initialLabel {
                        Button {
                            var copy = cfg
                            copy.label = initialLabel
                            appLayer.updateConfiguration(copy)
                        } label: {
                            Image(systemName: "arrow.uturn.backward.circle")
                                .imageScale(.small)
                        }
                        .buttonStyle(.borderless)
                        .help("还原为本条配置创建时的标签")
                    }
                }
                TextField("标签", text: Binding(
                    get: { cfg.label },
                    set: { newValue in
                        var copy = cfg
                        copy.label = newValue
                        appLayer.updateConfiguration(copy)
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .controlSize(.regular)
                .frame(maxWidth: 220, minHeight: 28)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text("Provider").font(.caption).foregroundStyle(.secondary)
                    if cfg.providerID != initialProviderID {
                        Button {
                            var copy = cfg
                            copy.providerID = initialProviderID
                            appLayer.updateConfiguration(copy)
                        } label: {
                            Image(systemName: "arrow.uturn.backward.circle")
                                .imageScale(.small)
                        }
                        .buttonStyle(.borderless)
                        .help("还原为本条配置创建时的 Provider")
                    }
                }
                TextField("provider id", text: Binding(
                    get: { cfg.providerID },
                    set: { newValue in
                        var copy = cfg
                        copy.providerID = newValue
                        appLayer.updateConfiguration(copy)
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .controlSize(.regular)
                .frame(maxWidth: 220, minHeight: 28)
            }
            Spacer()
        }
    }

    // MARK: - 编辑区

    private func editors(_ cfg: InjectionConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if cfg.kind == .official {
                HStack {
                    Text("auth.json (\(cfg.authJSON.count) 字符)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        appLayer.captureCurrentCodexState(into: cfg.id)
                    } label: {
                        Label("抓取当前 ~/.codex/auth.json 到这里", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("在终端跑完 `codex` 完成 ChatGPT 登录后，点此把当前真实状态保存到本条配置。")
                }
            } else {
                Text("auth.json (\(cfg.authJSON.count) 字符)").font(.caption).foregroundStyle(.secondary)
            }
            AutoResizingTextEditor(
                text: Binding(
                    get: { cfg.authJSON },
                    set: { newValue in
                        var copy = cfg
                        copy.authJSON = newValue
                        appLayer.updateConfiguration(copy)
                    }
                ),
                placeholder: "{ }",
                minHeight: 60,
                maxHeight: 320
            )

            Text("config.toml (\(cfg.configTOML.count) 字符)").font(.caption).foregroundStyle(.secondary)
            AutoResizingTextEditor(
                text: Binding(
                    get: { cfg.configTOML },
                    set: { newValue in
                        var copy = cfg
                        copy.configTOML = newValue
                        appLayer.updateConfiguration(copy)
                    }
                ),
                placeholder: "# TOML",
                minHeight: 60,
                maxHeight: 320
            )
        }
    }

    // MARK: - 底部操作

    private func bottomActions(_ cfg: InjectionConfiguration) -> some View {
        let isActive = (appLayer.activeInjection?.configurationID == cfg.id)
        return HStack(spacing: 12) {
            Button {
                appLayer.activateConfiguration(id: cfg.id)
            } label: {
                Label("激活此配置", systemImage: "bolt.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .tint(.green)
            .disabled(isActive)
            .help(isActive ? "当前已是激活状态" : "把当前编辑的 auth.json + config.toml 写入 ~/.codex/")

            Button {
                appLayer.deactivate()
            } label: {
                Label("恢复默认", systemImage: "arrow.uturn.backward.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(.gray)
            .disabled(!isActive)
            .help(isActive ? "清空 ~/.codex/auth.json + ~/.codex/config.toml，回到初始 Codex 状态" : "当前未激活，无需恢复")

            // 删除按钮（不依赖 contextMenu）：触发父层 confirmationDialog
            Button(role: .destructive) {
                pendingDeleteCodexConfig = cfg
            } label: {
                Label("删除", systemImage: "trash.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(.red)
            .frame(minWidth: 80, maxWidth: .infinity)
            .help("删除本条注入配置（清空编辑中的 auth.json + config.toml）")
        }
    }

    // MARK: - "已自动保存" 反馈辅助

    private static let autoSavedTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private func triggerAutoSaveToast() {
        autoSavedAt = Date()
    }

    private func autoSavedBadge(at date: Date) -> some View {
        StatusBadge(
            icon: "checkmark.seal.fill",
            text: "已自动保存 · \(Self.autoSavedTimeFormatter.string(from: date))",
            tint: .blue
        )
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: autoSavedAt)
    }
}
// MARK: - 自适应高度 TextEditor

struct AutoResizingTextEditor: View {
    @Binding var text: String
    var placeholder: String
    var minHeight: CGFloat = 60
    var maxHeight: CGFloat = 320

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(Color.black.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                )
                .frame(minHeight: minHeight, maxHeight: maxHeight)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

}
