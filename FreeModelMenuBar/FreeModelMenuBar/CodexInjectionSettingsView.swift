//
//  CodexInjectionSettingsView.swift
//  FreeModelMenuBar
//
//  单条注入配置的"详情区"。由 SettingsView 在右侧主区域渲染。
//  不再有 sheet / popover / DisclosureGroup / swipeActions。
//  顶部：标签 + Provider 两个文本框；右上角绿色「激活」/ 灰底「已激活 ✓」按钮。
//  中间：auth.json + config.toml 两个自适应高度编辑框（官方配置在 auth.json 上方提供抓取链接）。
//  底部：「停用该注入」（= 删 ~/.codex/auth.json + config.toml）。
//

import SwiftUI

struct CodexInjectionSettingsView: View {
    @ObservedObject var appLayer: AppLayer
    let configurationID: String

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
            activateButton(cfg)
        }
    }

    @ViewBuilder
    private func activateButton(_ cfg: InjectionConfiguration) -> some View {
        let isActive = (appLayer.activeInjection?.configurationID == cfg.id)
        if isActive {
            HStack(spacing: 8) {
                Label("已激活", systemImage: "checkmark.circle.fill")
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.2))
                    )
                    .foregroundStyle(.green)
            }
        } else {
            Button {
                appLayer.activateConfiguration(id: cfg.id)
            } label: {
                Label("激活", systemImage: "bolt.fill")
                    .frame(minWidth: 80)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
    }

    // MARK: - 标签 + Provider

    private func labelsAndProvider(_ cfg: InjectionConfiguration) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("标签").font(.caption).foregroundStyle(.secondary)
                TextField("标签", text: Binding(
                    get: { cfg.label },
                    set: { newValue in
                        var copy = cfg
                        copy.label = newValue
                        appLayer.updateConfiguration(copy)
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Provider").font(.caption).foregroundStyle(.secondary)
                TextField("provider id", text: Binding(
                    get: { cfg.providerID },
                    set: { newValue in
                        var copy = cfg
                        copy.providerID = newValue
                        appLayer.updateConfiguration(copy)
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
            }
            Spacer()
        }
    }

    // MARK: - 编辑区

    private func editors(_ cfg: InjectionConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if cfg.kind == .official {
                HStack {
                    Text("auth.json").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        appLayer.captureCurrentCodexState(into: cfg.id)
                    } label: {
                        Label("抓取当前 ~/.codex/auth.json 到这里", systemImage: "square.and.arrow.down")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("在终端跑完 `codex` 完成 ChatGPT 登录后，点此把当前真实状态保存到本条配置。")
                }
            } else {
                Text("auth.json").font(.caption).foregroundStyle(.secondary)
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

            Text("config.toml").font(.caption).foregroundStyle(.secondary)
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
            Button(role: .destructive) {
                appLayer.deactivate()
            } label: {
                Label("停用该注入（删除 ~/.codex/auth.json + config.toml）", systemImage: "arrow.uturn.backward.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            .disabled(!isActive)
        }
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
