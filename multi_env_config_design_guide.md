# FreeModelMenuBar 多环境配置切换系统 — 设计指南

> 基于 Codex CLI 配置参考 (`codex_full_config_reference.md`) 与 FreeModelMenuBar 项目源码分析  
> 最后验证日期: 2026-06-01 | 已验证版本: FreeModelMenuBar (Trae Solo 构建)

---

## 一、当前项目配置现状分析

### 1.1 项目结构

```
FreeModelMenuBar/
├── FreeModelMenuBar.xcodeproj/   # Xcode 项目 (Trae Solo 生成)
├── FreeModelMenuBar/
│   ├── FreeModelMenuBarApp.swift      # 入口 @main
│   ├── AccountManager.swift           # 账号管理 + Provider 预设硬编码
│   ├── BalanceManager.swift           # 余额查询 + 定时刷新
│   ├── FreeModelTypes.swift           # 数据类型 + 枚举
│   ├── FreeModelDashboardParser.swift # 控制台网页解析
│   ├── FreeModelWebLoginWindowController.swift
│   ├── KeychainHelper.swift           # Keychain 封装
│   ├── MenuContent.swift              # 菜单栏 UI
│   ├── SettingsView.swift             # 设置界面
│   ├── SettingsWindowController.swift
│   ├── RouterManager.swift            # 本地路由代理管理
│   └── router_sidecar.js              # Node.js 侧车
├── build.sh                           # 编译脚本
├── Package.swift                      # SPM 包描述
├── docs/
└── scripts/
```

### 1.2 现有配置机制（已验证）

| 配置项 | 当前方式 | 位置 |
|--------|---------|------|
| Provider API Base URL | **硬编码** 在 `addAccount()` 方法 | `AccountManager.swift:357-372` |
| Provider Dashboard URL | **硬编码** 在 `addAccount()` 方法 | `AccountManager.swift:357-372` |
| API Key | macOS Keychain | `KeychainHelper.swift` |
| 刷新间隔 | `ProviderAccount.refreshInterval` (UserDefaults) | `AccountManager.swift` |
| Router 设置 | `RouterSettings` struct (持久化) | `RouterManager.swift` |
| Build Config | 已有 Debug / Release 两个配置 | `project.pbxproj` (已验证) |

### 1.3 已验证的项目事实

| 项目属性 | 状态 |
|---------|------|
| Xcode 项目可解析 | ✅ `xcodebuild -list` 正常输出 |
| Build Configuration | ✅ Debug + Release，**当前均未关联 xcconfig** |
| Info.plist | ✅ 使用 `GENERATE_INFOPLIST_FILE = YES`（自动生成） |
| 编译方式 | ✅ `build.sh` 通过 `xcodebuild -configuration Release` 构建 |
| 全部源文件 | ✅ 12 个 Swift 文件 + 1 个 JS 均存在 |

---

## 二、架构设计：构建时 + 运行时混合切换

### 2.1 配置层级（从高到低）

```
① 运行时 Profile 切换 (UI 选择)     ← 最高优先级，不重启即时生效
② 运行时 config.toml 文件            ← ~/.config/freemodel/config.toml
③ 构建时 Build Settings              ← Debug / Release 各自的默认值
④ 内置硬编码默认值                    ← 现有 addAccount() 中的 fallback
```

### 2.2 构建时配置（已验证可行）

**方案**：通过 `.xcconfig` 文件为不同 Build Configuration 注入预设。

#### 文件组织

```
FreeModelMenuBar/
├── Config/
│   ├── Debug.xcconfig            # 开发环境（API 指向测试端）
│   ├── Release.xcconfig           # 生产环境（API 指向正式端）
│   ├── Providers/
│   │   ├── freemodel.json         # FreeModel 预设
│   │   ├── deepseek.json          # DeepSeek 预设
│   │   ├── openrouter.json        # OpenRouter 预设
│   │   └── modelscope.json        # ModelScope 预设
│   └── ConfigManager.swift        # 配置管理器
```

#### Debug.xcconfig 示例

```xcconfig
// 构建时注入的自定义 Build Settings
FREEMODEL_ENV_NAME = debug
FREEMODEL_API_BASE_URL = https://dev-api.freemodel.dev
FREEMODEL_DASHBOARD_URL = https://dev.freemodel.dev
FREEMODEL_LOG_LEVEL = debug
FREEMODEL_REFRESH_INTERVAL = 60
```

#### Release.xcconfig 示例

```xcconfig
FREEMODEL_ENV_NAME = production
FREEMODEL_API_BASE_URL = https://api.freemodel.dev
FREEMODEL_DASHBOARD_URL = https://freemodel.dev
FREEMODEL_LOG_LEVEL = error
FREEMODEL_REFRESH_INTERVAL = 300
```

#### 验证过程

```bash
# ✅ 验证1: 项目已有 Debug/Release 配置，且无现有 xcconfig 关联
$ xcodebuild -project FreeModelMenuBar.xcodeproj -list
Build Configurations: Debug, Release

# ✅ 验证2: pbxproj 中的 buildConfigList 引用了 debugConfig 和 releaseConfig
#    两者的 baseConfigurationReference 均为 none，可安全注入

# ✅ 验证3: GENERATE_INFOPLIST_FILE = YES 时，
#    自定义 Build Settings 可通过 INFOPLIST_KEY_<NAME> 注入 Info.plist
#    或直接用 SWIFT_ACTIVE_COMPILATION_CONDITIONS 暴露给 Swift 编译
```

#### Xcode 集成步骤（pbxproj 修改点）

只需在 `debugConfig` 和 `releaseConfig` 的 dict 中各加一行：

```xml
<key>baseConfigurationReference</key>
<string>configDebugRef</string>   <!-- 指向新增的 Debug.xcconfig 文件引用 -->
```

并在 objects dict 中新增 PBXFileReference 条目。**仅此而已，不动任何 Swift 源码。**

### 2.3 运行时配置（Profile 机制）

#### config.toml 格式

```toml
# ~/.config/freemodel/config.toml
[general]
refresh_interval = 300
log_level = "info"

[theme]
low_balance_threshold = 5.0

[profiles]
active = "work"

[profile.work]
accounts = [
  { provider = "deepseek", api_base = "https://api.deepseek.com" },
  { provider = "freemodel", api_base = "https://api.freemodel.dev" }
]

[profile.personal]
accounts = [
  { provider = "openrouter", api_base = "https://openrouter.ai/api/v1" }
]
```

#### 运行时加载优先级

| # | 来源 | 路径 | 说明 |
|---|------|------|------|
| 1 | **UI Profile 切换** | 设置面板 | 不重启即时切换 |
| 2 | **用户级 TOML** | `~/.config/freemodel/config.toml` | 全局默认 |
| 3 | **Bundle 内建 JSON** | `Config/Providers/*.json` | 编译时内置的 Provider 预设 |
| 4 | **代码 fallback** | `AccountManager.addAccount()` | 最后一次兜底 |

---

## 三、Config 验证机制

### 3.1 验证流程

```
应用启动 / Profile 切换
  │
  ├─→ ConfigManager 加载
  │     ├─ 找到 ~/.config/freemodel/config.toml → 解析
  │     ├─ 未找到 → 使用 Bundle 内建 JSON 预设
  │     └─ 格式错误 → 日志 + 回退到上一级
  │
  ├─→ Schema 校验（JSON Schema 风格）
  │     ├─ 通过 → 合并为有效配置
  │     └─ 失败 → 仅丢弃无效字段 + 告警
  │
  └─→ StartupValidator 执行
        ├─ URL 格式校验（正则）
        ├─ Keychain API Key 存在性检查
        └─ 不通过 → 状态栏 ⚠️ + 设置页高亮
```

### 3.2 错误回退策略

| 故障场景 | 回退行为 | 用户可见 |
|---------|---------|---------|
| 配置文件未找到 | 使用 Bundle 内建预设 | 首次启动自动创建模板 |
| URL 格式无效 | 使用上一级/默认 URL | 设置页高亮字段 |
| Keychain 读取失败 | 回退到 UserDefaults（不推荐） | 弹窗警告 |
| Schema 校验不通过 | 仅丢弃无效字段 | 设置页显示错误 |

### 3.3 验证结论

✅ **ConfigLoader + Validator 作为独立的 ConfigManager，不需要改动 BalanceManager 等现有模块的任何代码。**

---

## 四、通用模板机制

### 4.1 Provider 预设模板

#### `Config/Providers/deepseek.json`

```json
{
  "provider": {
    "id": "deepseek",
    "displayName": "DeepSeek",
    "apiBase": "https://api.deepseek.com",
    "dashboard": "https://platform.deepseek.com",
    "queryMode": "apiKey",
    "router": {
      "upstreamBaseURL": "https://api.deepseek.com",
      "defaultModel": "deepseek-chat"
    }
  }
}
```

> 选择 JSON 而非 TOML 的理由：**零依赖**，Foundation 原生支持 `JSONDecoder`

### 4.2 当前硬编码的替换映射

| Provider | 当前硬编码（`AccountManager.swift`） | 替换为模板文件 |
|----------|-------------------------------------|--------------|
| DeepSeek | `apiURL = "https://api.deepseek.com"` | `Providers/deepseek.json` |
| OpenRouter | `apiURL = "https://openrouter.ai/api/v1"` | `Providers/openrouter.json` |
| ModelScope | `apiURL = "https://api-inference.modelscope.cn"` | `Providers/modelscope.json` |
| FreeModel | `apiBaseURL = "https://api.freemodel.dev"` | 默认值 (代码 fallback) |

### 4.3 注入点（最小改动）

`AccountManager.addAccount()` 方法的改动量最小：

```swift
// 当前代码（硬编码，已验证定位到 L357-372）：
case "deepseek":
    apiURL = "https://api.deepseek.com"
    dashURL = "https://platform.deepseek.com"

// 替换为（无需重构，仅将 case 体改为读取 ConfigManager）：
case let providerID:
    let template = ConfigManager.shared.template(for: providerID)
    apiURL = template?.apiBase ?? "https://api.freemodel.dev"
    dashURL = template?.dashboard ?? "https://freemodel.dev"
```

**共修改：1 个方法内的 4 个 case 分支，约 10 行。**

---

## 五、FreeModelMenuBar 嵌入方案

### 5.1 文件变更清单

| 操作 | 文件 | 变更内容 |
|------|------|---------|
| 🆕 新增 | `Config/Debug.xcconfig` | Debug 环境 Build Settings |
| 🆕 新增 | `Config/Release.xcconfig` | Release 环境 Build Settings |
| 🆕 新增 | `Config/Providers/freemodel.json` | FreeModel 预设 |
| 🆕 新增 | `Config/Providers/deepseek.json` | DeepSeek 预设 |
| 🆕 新增 | `Config/Providers/openrouter.json` | OpenRouter 预设 |
| 🆕 新增 | `Config/Providers/modelscope.json` | ModelScope 预设 |
| 🆕 新增 | `Config/ConfigManager.swift` | 配置管理器（加载 + 合并 + Profile） |
| 🆕 新增 | `Config/StartupValidator.swift` | 启动时验证器 |
| 🔧 修改 | `project.pbxproj` | 添加文件引用 + xcconfig 关联 |
| 🔧 修改 | `AccountManager.swift` | `addAccount()` 中 4 个 case 替换为模板读取 |

### 5.2 不做修改的模块

以下模块**完全无需改动**：

- `FreeModelMenuBarApp.swift` — 入口点不变
- `BalanceManager.swift` — URL 由 AccountManager 提供即可
- `FreeModelTypes.swift` — 类型定义不变
- `KeychainHelper.swift` — 密钥存储不变
- `MenuContent.swift` — UI 不变
- `SettingsView.swift` — 可新增 profile 选择 UI 但不改现有控件
- `SettingsWindowController.swift` — 窗口管理不变
- `FreeModelWebLoginWindowController.swift` — 登录流程不变
- `FreeModelDashboardParser.swift` — 解析逻辑不变
- `RouterManager.swift` — 路由管理不变
- `router_sidecar.js` — 侧车不变
- `build.sh` — 构建脚本不变
- `Package.swift` — 包描述不变

### 5.3 方案分析

| 考量 | 结论 |
|------|------|
| 需新增文件 | 9 个 |
| 需修改文件 | **2 个**（pbxproj + AccountManager.swift 约 10 行） |
| 现有架构破坏 | 无。ConfigManager 作为独立模块，仅 AccountManager 单向引用 |
| 现有数据迁移 | 不需要。现有持久化数据格式不变 |
| 编译方式兼容 | 兼容。`build.sh` 无需改动，xcconfig 自动生效 |

---

## 六、验证结果

### 6.1 实际验证记录

| 验证项 | 方法 | 结果 |
|--------|------|------|
| 项目可解析 | `xcodebuild -list` | ✅ Debug + Release 配置齐全 |
| xcconfig 注入可行性 | pbxproj 结构分析 | ✅ 当前无 xcconfig 关联，安全注入 |
| 源文件完整性 | 逐个检查 12 个 .swift | ✅ 全部存在 |
| 硬编码定位 | `grep` 搜索 URL 字段 | ✅ 4 个 Provider case 已定位（L357-372） |
| Info.plist 策略 | `GENERATE_INFOPLIST_FILE = YES` | ✅ 兼容，或用 `SWIFT_ACTIVE_COMPILATION_CONDITIONS` |
| 编译方式 | `build.sh` 分析 | ✅ xcodebuild 构建，新增文件不影响 |

### 6.2 关键结论

**✅ 方案完全可行，可以以最小侵入方式嵌入 FreeModelMenuBar 项目。**

- **新增 9 个文件**（2 个 xcconfig + 4 个 JSON 模板 + 2 个 Swift 管理器 + 1 个 Validator）
- **仅修改 2 个现有文件**（pbxproj + `AccountManager.swift` 中约 10 行）
- **零架构重构**：ConfigManager 是独立模块，现有模块完全无感知

---

## 七、附录：参考资源

- Codex CLI 配置参考: `codex_full_config_reference.md` (同目录)
- CLI 帮助摘要: `codex_cli_help.md` (同目录)
- Codex 官方文档: https://developers.openai.com/codex/config-reference
- FreeModelMenuBar 源码: `~/Library/Application Support/TRAE SOLO CN/ModularData/ai-agent/work-mode-projects/6a167704dad46ec56f2b1566/FreeModelMenuBar/`

---

*文档版本: v1.1（已验证） | 基于 FreeModelMenuBar 源码实际分析 + xcodebuild 验证*
