//
//  RouterSettingsView.swift
//  FreeModelMenuBar
//
//  路由配置 + 自定义 URL + 刷新频率（原 SettingsView 路由段）
//

import SwiftUI

// MARK: - Provider Preset（4 种预设，1 次点击设齐 6 个字段）

enum ProviderPreset: String, CaseIterable, Identifiable {
    case freeModel = "FreeModel"
    case deepseek = "DeepSeek"
    case openRouter = "OpenRouter"
    case modelScope = "ModelScope"
    var id: String { rawValue }

    struct Config {
        let apiURL: String
        let dashboardURL: String
        let queryMode: QueryMode
        let routerUpstream: String
        let defaultModel: String
        let routeModel: String
    }

    var config: Config {
        Self.config(for: self)
    }

    private static let freeModelConfig = Config(
        apiURL: "https://api.freemodel.dev",
        dashboardURL: "https://freemodel.dev",
        queryMode: .dashboard,
        routerUpstream: "https://api.freemodel.dev/v1",
        defaultModel: "codex-mini",
        routeModel: "codex-mini"
    )

    private static let deepseekConfig = Config(
        apiURL: "https://api.deepseek.com",
        dashboardURL: "https://platform.deepseek.com",
        queryMode: .apiKey,
        routerUpstream: "https://api.deepseek.com/v1",
        defaultModel: "deepseek-chat",
        routeModel: "codex-mini"
    )

    private static let openRouterConfig = Config(
        apiURL: "https://openrouter.ai/api/v1",
        dashboardURL: "https://openrouter.ai",
        queryMode: .apiKey,
        routerUpstream: "https://openrouter.ai/api/v1",
        defaultModel: "deepseek/deepseek-v4-flash:free",
        routeModel: "codex-mini"
    )

    private static let modelScopeConfig = Config(
        apiURL: "https://api-inference.modelscope.cn",
        dashboardURL: "https://modelscope.cn",
        queryMode: .apiKey,
        routerUpstream: "https://api-inference.modelscope.cn/v1",
        defaultModel: "ZhipuAI/GLM-5.1",
        routeModel: "codex-mini"
    )

    private static func config(for preset: ProviderPreset) -> Config {
        switch preset {
        case .freeModel: return freeModelConfig
        case .deepseek: return deepseekConfig
        case .openRouter: return openRouterConfig
        case .modelScope: return modelScopeConfig
        }
    }
}

// MARK: - RouterEditingState（替代 16 个独立 @State）

struct RouterEditingState: Equatable {
    var enabled: Bool = false
    var port: String = "38440"
    var upstreamURL: String = ""
    var routeModel: String = ""
    var defaultModel: String = ""
    var streaming: Bool = true
    var failoverEnabled: Bool = true
    var maxConcurrency: String = "0"
    var minIntervalMs: String = "0"
}

extension RouterEditingState {
    init(from settings: RouterSettings) {
        self.enabled = settings.enabled
        self.port = String(settings.port)
        self.upstreamURL = settings.upstreamBaseURL
        self.routeModel = settings.routeModel
        self.defaultModel = settings.defaultModel
        self.streaming = settings.supportsStreaming
        self.failoverEnabled = settings.isFailoverEnabled ?? true
        self.maxConcurrency = String(settings.maxConcurrency ?? 0)
        self.minIntervalMs = String(settings.minIntervalMs ?? 0)
    }

    func toRouterSettings() -> RouterSettings {
        RouterSettings(
            enabled: enabled,
            port: Int(port) ?? 38440,
            upstreamBaseURL: upstreamURL.trimmingCharacters(in: .whitespacesAndNewlines),
            routeModel: routeModel.trimmingCharacters(in: .whitespacesAndNewlines),
            defaultModel: defaultModel.trimmingCharacters(in: .whitespacesAndNewlines),
            supportsStreaming: streaming,
            maxConcurrency: Int(maxConcurrency) ?? 0,
            minIntervalMs: Int(minIntervalMs) ?? 0,
            failoverEnabled: failoverEnabled
        )
    }
}

// MARK: - RouterSettingsView

struct RouterSettingsView: View {
    let accountID: UUID
    @ObservedObject var accountManager: AccountManager
    @ObservedObject var routerManager: RouterManager
    @Binding var pendingScrollToAPIKey: Bool

    private var account: ProviderAccount? {
        accountManager.account(id: accountID)
    }

    @State private var editing = RouterEditingState()
    @State private var initial = RouterEditingState()
    @State private var apiURLInput: String = ""
    @State private var initialApiURL: String = ""
    @State private var dashboardURLInput: String = ""
    @State private var initialDashboardURL: String = ""
    @State private var selectedRefreshInterval: TimeInterval = 300

    private let refreshOptions: [(String, TimeInterval)] = [
        ("1 分钟", 60),
        ("5 分钟", 300),
        ("10 分钟", 600),
        ("30 分钟", 1800),
        ("1 小时", 3600)
    ]

    var body: some View {
        sectionVStack {
            routerContent
            customURLsSection
            refreshSection
        }
        .onAppear(perform: loadFromAccount)
        .onChange(of: accountID) { _ in loadFromAccount() }
    }

    private func loadFromAccount() {
        guard let account else { return }
        let s = account.activeRouterSettings
        editing = RouterEditingState(from: s)
        initial = RouterEditingState(from: s)
        apiURLInput = account.apiBaseURL
        initialApiURL = account.apiBaseURL
        dashboardURLInput = account.dashboardURL
        initialDashboardURL = account.dashboardURL
        selectedRefreshInterval = account.refreshInterval
    }

    // MARK: - 路由主内容

    private var hasAPIKey: Bool { account?.hasAPIKey ?? false }

    private var routerContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("本地 Responses 路由代理", systemImage: "arrow.triangle.2.circlepath.circle")
                    .font(.headline)
                if editing != initial {
                    Image(systemName: "circle.dashed")
                        .foregroundStyle(.orange)
                        .imageScale(.small)
                    Text("未保存")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Spacer()
                HStack(spacing: 6) {
                    Text(routerManager.status.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let dot = routerManager.status.statusColor {
                        statusDot(color: dot, help: "路由代理状态")
                    }
                }
            }

            Text("为当前账号开启本地端口代理，将输入的 Responses 协议请求（如 Codex/cc switch 客户端发来）自动中转为 Chat Completions 协议发送给上游服务商。")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Switch
            HStack {
                Toggle(isOn: Binding(
                    get: { editing.enabled },
                    set: { editing.enabled = $0 }
                )) {
                    Text(toggleLabel(routerEnabled: editing.enabled, hasAPIKey: hasAPIKey))
                        .fontWeight(.semibold)
                        .foregroundStyle(hasAPIKey ? Color.primary : .red)
                }
                .disabled(!hasAPIKey)

                Spacer()
            }
            .padding(.vertical, 4)

            // 缺 API Key 提示
            if !hasAPIKey {
                missingAPIKeyWarning
            }

            // Preset chips
            HStack(spacing: 6) {
                Text("预设:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(ProviderPreset.allCases) { preset in
                    providerPresetChip(preset: preset)
                }
            }
            .padding(.bottom, 4)

            if editing.enabled {
                routerFields
            }
        }
        .sectionPanel()
    }

    // MARK: - 缺 API Key 警告

    private var missingAPIKeyWarning: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("未配置 API Key")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.red)
                Text("启用本地路由代理需要 API Key，请先在上方「连接」段配置并测试。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("去配置") {
                pendingScrollToAPIKey = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.orange)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.red.opacity(0.3), lineWidth: 1))
        .padding(.bottom, 4)
    }

    // MARK: - 路由字段

    private var routerFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("带")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("*")
                    .font(.caption2)
                    .foregroundStyle(.red)
                Text("的字段不能为空。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            // 代理设置
            VStack(alignment: .leading, spacing: 8) {
                Label("代理设置", systemImage: "network")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    requiredRouterField(
                        label: "本地代理端口",
                        placeholder: "38440",
                        text: $editing.port,
                        fieldWidth: 80
                    )
                    requiredRouterField(
                        label: "上游 API Base URL",
                        placeholder: "https://api.deepseek.com/v1",
                        text: $editing.upstreamURL,
                        fieldWidth: nil
                    )
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.05)))

            // 模型映射
            VStack(alignment: .leading, spacing: 8) {
                Label("模型映射", systemImage: "arrow.left.arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                requiredRouterField(
                    label: "对外暴露模型名",
                    placeholder: "codex-mini",
                    text: $editing.routeModel,
                    fieldWidth: nil
                )
                requiredRouterField(
                    label: "映射到上游模型名",
                    placeholder: "deepseek-chat",
                    text: $editing.defaultModel,
                    fieldWidth: nil
                )
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.05)))

            // 并发 + 间隔
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("最大并发数 (0为无限制)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("0", text: $editing.maxConcurrency)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("最小请求间隔 (毫秒, 0为无限制)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("0", text: $editing.minIntervalMs)
                        .textFieldStyle(.roundedBorder)
                }
            }

            // Toggle 行
            HStack(spacing: 20) {
                Toggle("流式响应 (Streaming)", isOn: $editing.streaming)
                    .font(.caption)
                Toggle("自动灾备转移 (Failover)", isOn: $editing.failoverEnabled)
                    .font(.caption)
                Spacer()
            }

            // 保存按钮
            HStack {
                Spacer()
                Button(editing != initial ? "保存及重载配置" : "已保存") {
                    saveRouterSettings()
                    initial = editing
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .frame(height: 28)
                .disabled(!routerIsValid() || editing == initial)
            }
            .padding(.top, 4)
        }
        .padding(.all, 10)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.05)))
    }

    // MARK: - 自定义服务器地址

    private var customURLsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("自定义服务器地址", systemImage: "network")
                .font(.headline)

            Text("要快速切换 provider（URL + 查询模式 + 路由 + 默认模型 一次性设齐）？请到上方「路由代理」开关下方的预设 chip。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text("控制台网页 Base URL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if dashboardURLInput.trimmingCharacters(in: .whitespacesAndNewlines) != initialDashboardURL {
                        Image(systemName: "circle.dashed")
                            .foregroundStyle(.orange)
                            .imageScale(.small)
                        Text("未保存")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                TextField("https://freemodel.dev", text: $dashboardURLInput)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text("API Base URL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if apiURLInput.trimmingCharacters(in: .whitespacesAndNewlines) != initialApiURL {
                        Image(systemName: "circle.dashed")
                            .foregroundStyle(.orange)
                            .imageScale(.small)
                        Text("未保存")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                TextField("https://api.freemodel.dev", text: $apiURLInput)
                    .textFieldStyle(.roundedBorder)
            }

            Button("保存服务器地址") {
                accountManager.updateURLs(apiURL: apiURLInput, dashboardURL: dashboardURLInput, for: accountID)
                initialApiURL = apiURLInput
                initialDashboardURL = dashboardURLInput
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .frame(height: 28)
            .disabled(apiURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                      dashboardURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .sectionPanel()
    }

    // MARK: - 自动刷新频率

    private var refreshSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("自动刷新频率", systemImage: "clock.fill")
                .font(.headline)

            Picker("刷新频率", selection: $selectedRefreshInterval) {
                ForEach(refreshOptions, id: \.1) { label, interval in
                    Text(label).tag(interval)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedRefreshInterval) { newValue in
                accountManager.updateRefreshInterval(newValue, for: accountID)
            }

            Text("控制台模式自动重新抓取余额的频率。API Key 模式不消耗此设置。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .sectionPanel()
    }

    // MARK: - Helper views

    private func toggleLabel(routerEnabled: Bool, hasAPIKey: Bool) -> String {
        if !hasAPIKey { return "请先配置 API Key" }
        return routerEnabled ? "正在运行代理" : "启用本地路由代理"
    }

    private func routerFieldEmpty(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func routerIsValid() -> Bool {
        !routerFieldEmpty(editing.port)
            && !routerFieldEmpty(editing.upstreamURL)
            && !routerFieldEmpty(editing.routeModel)
            && !routerFieldEmpty(editing.defaultModel)
    }

    @ViewBuilder
    private func requiredRouterField(label: String, placeholder: String, text: Binding<String>, fieldWidth: CGFloat?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if routerFieldEmpty(text.wrappedValue) {
                    Text("*")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            let textField = TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(routerFieldEmpty(text.wrappedValue) ? .red.opacity(0.6) : .clear, lineWidth: 1.5))
            if let fieldWidth = fieldWidth {
                textField.frame(width: fieldWidth)
            } else {
                textField
            }
        }
    }

    private func isPresetActive(_ preset: ProviderPreset) -> Bool {
        account?.apiBaseURL == preset.config.apiURL
    }

    private func providerPresetChip(preset: ProviderPreset) -> some View {
        let active = isPresetActive(preset)
        return Group {
            if active {
                Button(preset.rawValue) { applyProviderPreset(preset) }
                    .buttonStyle(.borderedProminent)
                    .help("当前账号正在使用此预设")
            } else {
                Button(preset.rawValue) { applyProviderPreset(preset) }
                    .buttonStyle(.bordered)
                    .help("1 次点击套用 \(preset.rawValue) 的 URL+查询模式+路由+默认模型+Streaming+Failover")
            }
        }
        .controlSize(.small)
    }

    private func applyProviderPreset(_ preset: ProviderPreset) {
        let cfg = preset.config
        accountManager.updateURLs(apiURL: cfg.apiURL, dashboardURL: cfg.dashboardURL, for: accountID)
        accountManager.updateQueryMode(cfg.queryMode, for: accountID)
        editing.upstreamURL = cfg.routerUpstream
        editing.defaultModel = cfg.defaultModel
        editing.routeModel = cfg.routeModel
        editing.streaming = true
        editing.failoverEnabled = true
        saveRouterSettings()
        loadFromAccount()
    }

    private func saveRouterSettings() {
        let newSettings = editing.toRouterSettings()
        accountManager.updateRouterSettings(newSettings, for: accountID)
        routerManager.syncStateWithActiveAccount()
    }
}
