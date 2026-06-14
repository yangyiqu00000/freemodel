# FreeModel MenuBar - macOS 状态栏余额监控与本地 Responses 代理

一个专为开发者打造的轻量级 macOS 菜单栏应用，不仅可以实时监控并预警你的 FreeModel、DeepSeek、OpenRouter、ModelScope 账户余额与 API 额度，还内置了高性能的本地 **Responses 协议转译路由代理服务器**，完美适配 Cursor、Codex 等 AI 编辑器客户端。

---

## ✨ 功能特性

### 1. 📊 多账户额度与余额监控
- **多账户独立隔离**：支持同时添加、管理多个不同的 API 账户（支持 FreeModel、DeepSeek、OpenRouter、ModelScope 等）。
- **双模式额度刷新**：
  - **网页控制台模式**：通过内置隔离的 WebKit 窗口安全登录 FreeModel 控制台，自动抓取会话 Cookie，无需暴露 API Key。
  - **API Key 模式**：通过直接调用对应服务商的标准 billing 接口查询额度，提供极速获取体验。
- **状态栏直观预警**：直接在 macOS 菜单栏显示当前账号余额。支持自定义额度警戒线，颜色随余额状态动态渐变（绿色 正常 ➡️ 橙色 偏低 ➡️ 红色 告急）。
- **多维度常用预设**：一键应用主流服务商（FreeModel、DeepSeek、OpenRouter、ModelScope）的 API 地址、控制台及路由预设。

### 2. ⚡ 本地 Responses 协议路由中转（Node.js 侧车）
- **Responses ➡️ Chat Completions 协议互转**：在本地拉起轻量级中转服务（`http://127.0.0.1:{port}/v1`），自动将客户端发起的 Responses 协议请求（Cursor 等所用协议）转换为标准的 OpenAI Chat Completions 协议发送至您的上游服务商。
- **智能角色映射（Developer ➡️ System）**：自动将最新协议中的 `developer` 角色智能映射为上游大模型所需的 `system` 角色，彻底杜绝上游解析器抛出 `unknown variant developer` 导致的 400 报错。
- **连接自适应清理（防残留）**：实时监听 `res.on('close')` 与 `res.writableFinished`，一旦客户端主动取消生成（如在 Cursor 中停止生成），代理将立即销毁上游 TCP 请求，杜绝 Token 额度浪费与带宽占用。
- **Responses 标准错误流集成**：在发生错误或上游请求失败时，自动将其包装为标准的 `event: response.failed` SSE 事件，使客户端能够优雅解码异常信息。
- **零依赖与无状态设计**：代理进程纯粹由 Node.js 内置模块实现，零 npm 依赖；所有配置通过环境变量在 Swift 启动进程时直接注入，在磁盘上不留任何临时配置文件。

### 3. 🛠️ 开发者级控制台 UI
- **完全对齐的卡片布局**：设置界面各功能模块（账号信息、额度查询、API Key、本地路由、自定义地址等）自适应撑满容器，左右完美垂直对齐，提供原生 macOS 系统级的视觉质感。
- **深色日志控制台**：直观展示最近 50 条代理请求的结构化日志（时间、请求方式、本地模型、状态码、上游响应延迟、报错详情等），并支持一键清除，方便调试。
- **快捷链接集成**：根据当前选中的账户提供商，动态显示对应服务商的控制台登录入口以及精准的 API 官方文档跳转链接。

---

## 📋 系统要求

- macOS 13.0 (Ventura) 或更高版本
- Xcode 15+（用于本地编译）
- Node.js 16+（用于运行本地路由代理侧车）
- Swift 5.9+

---

## 🚀 快速开始

### 1. 编译并安装应用

通过终端执行自带的自动化编译脚本：
```bash
./build.sh
```

> [!TIP]
> 编译成功后，脚本会自动清理旧版本的 macOS 内核代码页缓存并清除扩展属性，接着对其重新签名，最后复制到您的桌面：`~/Desktop/FreeModelMenuBar.app`。双击即可完美运行，有效避免 macOS 因本地 ad-hoc 签名缓存导致的 `Invalid Page` 闪退。

### 2. 配置并运行路由代理

1. 启动 `FreeModelMenuBar.app`，点击状态栏的 💲 图标，进入 **设置**。
2. 点击右上角 **`+`** 按钮，选择并新建对应渠道的 API 账号（例如 `DeepSeek API 账号` 或 `ModelScope API 账号`）。
3. 填入您的上游 API Key 并保存。
4. 滚动到 **本地 Responses 路由代理** 区域：
   - 勾选 **启用本地路由代理**。
   - 选择对应的 **上游预设**（如 `DeepSeek`、`ModelScope`、`OpenRouter`）。
   - 点击 **保存及重载配置**。
5. 待右上角状态变为 **运行中** 后，点击 **复制 Base URL**（如 `http://127.0.0.1:38440/v1`）。
6. 将复制的地址填入您的 Cursor 或是 `cc switch` 中，本地模型名映射为 `codex-mini`（或您自定义的暴露模型名），即可畅快使用。

---

## 🔧 技术架构

- **UI 框架**：SwiftUI + MenuBarExtra (macOS 13+)
- **生命周期与自愈**：利用 `NSWorkspace.didWakeNotification` 监听系统休眠唤醒。Mac 唤醒后，App 自动对运行中的代理端口进行健康检测，若意外断开则自动进行热重启自愈。
- **安全存储**：API Key 等敏感数据使用 macOS Keychain 安全托管。
- **进程管理**：通过 `Process` 管道管理拉起 Node.js 侧车子进程，并通过非阻塞 `readabilityHandler` 监听其 `standardOutput` 和 `standardError` 转换为日志面板数据。在主 App 意外退出时，进程 termination 机制能强杀子进程，防止端口残留。

---

## 🏗️ 项目结构

```
FreeModelMenuBar/
├── FreeModelMenuBar.xcodeproj/    # Xcode 项目工程文件
├── FreeModelMenuBar/
│   ├── FreeModelMenuBarApp.swift  # 应用主入口，处理 MenuBarExtra 与生命周期
│   ├── AccountManager.swift       # 多账户持久化管理，处理账号属性与路由预设
│   ├── RouterManager.swift        # 侧车进程生命周期管理、端口 bind 检测与日志管道
│   ├── router_sidecar.js          # 本地 Node.js 路由协议中转代理服务器 (Bundle Resource)
│   ├── BalanceManager.swift       # 余额与额度刷新核心逻辑
│   ├── KeychainHelper.swift       # Keychain 安全存储工具
│   ├── FreeModelTypes.swift       # 共享的实体结构与错误枚举
│   ├── FreeModelDashboardParser.swift # 网页版数据解析引擎
│   ├── SettingsView.swift         # 开发者设置主界面 (包括日志控制台)
│   └── MenuContent.swift          # 状态栏下拉状态卡片与快捷操作
├── scripts/                       # 自动化验证与测试套件
│   ├── check_router_responses_stream.js # 验证流式 SSE 协议翻译
│   ├── check_router_tool_calls.js       # 验证复杂工具调用与上下文修复
│   ├── check_account_manager.swift      # 验证账号状态持久化与迁移
│   └── check_settings_window.swift      # 验证窗口控制器依赖注入
├── Package.swift                  # Swift SPM 配置
└── build.sh                       # 一键安全编译与签名部署脚本
```

---

## 📝 注意事项

- **端口占用问题**：启动代理前，应用会通过 Network 框架的 `NWListener` 尝试临时 bind 设定端口，如果端口被占用，状态会标为 `端口占用` 且不会强行拉起 Node。请修改端口后再试。
- **Node.js 环境路径**：App 启动侧车需要调用系统中的 `node` 路径，应用会依次寻找 Brew 默认路径、系统默认路径、甚至是 NVM 等动态配置路径。如遇 `未能在系统中找到 node` 提示，请确保您的 Node.js 已经正确安装在系统 PATH 中。

---

## 📄 许可证

MIT License
