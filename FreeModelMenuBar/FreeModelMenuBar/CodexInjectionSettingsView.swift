//
//  CodexInjectionSettingsView.swift
//  FreeModelMenuBar
//
//  单条注入配置详情页 — 完全重做。
//
//  重做原因：旧实现把 auth.json / config.toml 放在自定义 NSTextView 里，
//  在 SwiftUI 嵌套下表现"全黑 + 滑到底能看见按钮 + 框/内容全不可见"。
//  根本原因在 NSTextView + NSAttributedString 路线，缝补无效。
//
//  新实现：
//  - 完全用 SwiftUI 原生控件（TextField / TextEditor）
//  - 外层：浅色卡片（regularMaterial 背景 + 显式边框），与右侧其它详情页视觉一致
//  - 编辑器：TextEditor + monospaced 字体 + 浅色背景 + 圆角边框，frame(minHeight: 200, idealHeight: 260, maxHeight: 320)
//  - 顶部：标题 + 激活/未激活徽章；自动保存反馈放在右上角
//  - 中部：标签 / Provider 两个输入框（带"还原"小按钮）
//  - 编辑区：auth.json + config.toml 两个 TextEditor，自带"抓取当前 ~/.codex 状态"按钮（仅官方配置）
//  - 底部：激活 / 恢复默认 / 删除 三按钮，永远在卡片底部固定可见
//

import SwiftUI

struct CodexInjectionSettingsView: View {
    @ObservedObject var appLayer: AppLayer
    let configurationID: String
    @Binding var pendingDeleteCodexConfig: InjectionConfiguration?

    // 创建时 label / providerID（用于 undo 按钮）
    @State private var initialLabel: String = ""
    @State private var initialProviderID: String = ""
    @State private var didCaptureInitial: Bool = false

    // "已自动保存"反馈
    @State private var autoSavedAt: Date? = nil
    @State private var clearSavedTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let cfg = currentConfig {
                content(for: cfg)
            } else {
                emptyState
            }
        }
        .task { await appLayer.refresh() }
    }

    // MARK: - 主内容

    @ViewBuilder
    private func content(for cfg: InjectionConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(for: cfg)
                .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    basicInfoSection(for: cfg)
                    editorsSection(for: cfg)
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: .infinity)

            Divider().padding(.vertical, 8)

            bottomActions(for: cfg)
        }
        .padding(20)
        .background(cardBackground)
        .overlay(cardBorder)
        .onAppear { captureInitialIfNeeded(cfg) }
        .onChange(of: cfg.label) { _ in triggerAutoSaveToast() }
        .onChange(of: cfg.providerID) { _ in triggerAutoSaveToast() }
        .onChange(of: cfg.authJSON) { _ in triggerAutoSaveToast() }
        .onChange(of: cfg.configTOML) { _ in triggerAutoSaveToast() }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "questionmark.circle")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("该注入配置已不存在。")
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    // MARK: - 头部

    private func header(for cfg: InjectionConfiguration) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "key.horizontal.fill")
                .font(.title2)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Codex 注入")
                    .font(.title2).fontWeight(.bold)
                Text(cfg.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            activeBadge(for: cfg)
            if let savedAt = autoSavedAt {
                autoSavedBadge(at: savedAt)
            }
        }
    }

    @ViewBuilder
    private func activeBadge(for cfg: InjectionConfiguration) -> some View {
        let isActive = (appLayer.activeInjection?.configurationID == cfg.id)
        if isActive, let activatedAt = appLayer.activeInjection?.activatedAt {
            HStack(spacing: 6) {
                StatusBadge(icon: "checkmark.circle.fill", text: "已激活", tint: .green)
                Text(activatedAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .help("激活于 \(activatedAt.formatted(date: .abbreviated, time: .standard))")
        } else {
            StatusBadge(icon: "circle.dashed", text: "未激活", tint: .secondary)
        }
    }

    // MARK: - 基本信息（标签 / Provider）

    private func basicInfoSection(for cfg: InjectionConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("基本信息", systemImage: "tag")
            HStack(alignment: .top, spacing: 16) {
                labeledTextField(
                    label: "标签",
                    placeholder: "标签",
                    text: bindingForLabel(cfg),
                    initialValue: initialLabel,
                    onRevert: { revertLabel(cfg) }
                )
                labeledTextField(
                    label: "Provider",
                    placeholder: "provider id",
                    text: bindingForProvider(cfg),
                    initialValue: initialProviderID,
                    onRevert: { revertProvider(cfg) }
                )
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - 编辑区（auth.json + config.toml）

    private func editorsSection(for cfg: InjectionConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("注入内容", systemImage: "doc.text")
            editorBlock(
                title: "auth.json",
                language: .json,
                charCount: cfg.authJSON.count,
                extraHeader: cfg.kind == .official ? AnyView(captureButton(for: cfg)) : nil,
                text: bindingForAuthJSON(cfg)
            )
            editorBlock(
                title: "config.toml",
                language: .toml,
                charCount: cfg.configTOML.count,
                extraHeader: nil,
                text: bindingForConfigTOML(cfg)
            )
        }
    }

    private func captureButton(for cfg: InjectionConfiguration) -> AnyView {
        AnyView(
            Button {
                appLayer.captureCurrentCodexState(into: cfg.id)
            } label: {
                Label("抓取当前 ~/.codex/auth.json", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("在终端跑完 `codex` 完成 ChatGPT 登录后，点此把当前真实状态保存到本条配置。")
        )
    }

    @ViewBuilder
    private func editorBlock(
        title: String,
        language: CodeLanguage,
        charCount: Int,
        extraHeader: AnyView?,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(title) (\(charCount) 字符)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let extra = extraHeader { extra }
            }
            CodeEditorView(text: text, language: language)
        }
    }

    // MARK: - 底部操作

    private func bottomActions(for cfg: InjectionConfiguration) -> some View {
        let isActive = (appLayer.activeInjection?.configurationID == cfg.id)
        return HStack(spacing: 10) {
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

            Button(role: .destructive) {
                pendingDeleteCodexConfig = cfg
            } label: {
                Label("删除", systemImage: "trash.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(.red)
            .help("删除本条注入配置（清空编辑中的 auth.json + config.toml）")
        }
        .frame(height: 32)
    }

    // MARK: - 通用小组件

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
    }

    private func labeledTextField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        initialValue: String,
        onRevert: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if text.wrappedValue != initialValue {
                    Button(action: onRevert) {
                        Image(systemName: "arrow.uturn.backward.circle")
                            .imageScale(.small)
                    }
                    .buttonStyle(.borderless)
                    .help("还原为创建时的 \(label)")
                }
            }
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .controlSize(.regular)
                .frame(minWidth: 180)
        }
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

    // MARK: - 辅助

    private var currentConfig: InjectionConfiguration? {
        appLayer.injectionConfigurations.first(where: { $0.id == configurationID })
    }

    private func captureInitialIfNeeded(_ cfg: InjectionConfiguration) {
        guard !didCaptureInitial else { return }
        initialLabel = cfg.label
        initialProviderID = cfg.providerID
        didCaptureInitial = true
    }

    private func triggerAutoSaveToast() {
        clearSavedTask?.cancel()
        autoSavedAt = Date()
        clearSavedTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            autoSavedAt = nil
        }
    }

    private static let autoSavedTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    // MARK: - Bindings / Revert helpers

    private func bindingForLabel(_ cfg: InjectionConfiguration) -> Binding<String> {
        Binding(
            get: { cfg.label },
            set: { newValue in
                var copy = cfg
                copy.label = newValue
                appLayer.updateConfiguration(copy)
            }
        )
    }

    private func bindingForProvider(_ cfg: InjectionConfiguration) -> Binding<String> {
        Binding(
            get: { cfg.providerID },
            set: { newValue in
                var copy = cfg
                copy.providerID = newValue
                appLayer.updateConfiguration(copy)
            }
        )
    }

    private func bindingForAuthJSON(_ cfg: InjectionConfiguration) -> Binding<String> {
        Binding(
            get: { cfg.authJSON },
            set: { newValue in
                var copy = cfg
                copy.authJSON = newValue
                appLayer.updateConfiguration(copy)
            }
        )
    }

    private func bindingForConfigTOML(_ cfg: InjectionConfiguration) -> Binding<String> {
        Binding(
            get: { cfg.configTOML },
            set: { newValue in
                var copy = cfg
                copy.configTOML = newValue
                appLayer.updateConfiguration(copy)
            }
        )
    }

    private func revertLabel(_ cfg: InjectionConfiguration) {
        var copy = cfg
        copy.label = initialLabel
        appLayer.updateConfiguration(copy)
    }

    private func revertProvider(_ cfg: InjectionConfiguration) {
        var copy = cfg
        copy.providerID = initialProviderID
        appLayer.updateConfiguration(copy)
    }
}
