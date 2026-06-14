# Codex CLI 完整配置参考

> 基于 OpenAI Codex CLI 源码 (v0.135.0+) 整理。涵盖 `config.toml` 所有顶层字段、嵌套类型、枚举值及环境变量注入方式。

---

## 一、配置层级与优先级（从高到低）

| # | 来源 | 文件 / 命令 | 说明 |
|---|------|------------|------|
| 1 | **CLI 参数 / 环境变量** | `codex --model gpt-4` | 仅本次会话生效，最高优先级 |
| 2 | **会话级 profile** | `--profile work` 或 `--profile v2:staging` | 加载指定 profile 进行覆盖 |
| 3 | **项目级配置** | `.codex/config.toml` | 当前工作目录及其父目录向上查找 |
| 4 | **跨项目信任表** | `~/.codex/config.toml` 中的 `[[projects]]` | 按路径匹配项目，附加 `trust_level` |
| 5 | **用户级配置** | `~/.codex/config.toml` | 用户偏好全局默认值 |
| 6 | **Requirements（管理员）** | `requirements.toml` | 企业/团队强制策略，可禁止用户覆盖 |
| 7 | **内置默认值** | 源码硬编码 | 当上层未提供时生效 |

### 配置搜索路径

| 平台 | 用户级 `config.toml` 路径 |
|------|--------------------------|
| macOS | `~/.codex/config.toml` |
| Linux | `~/.config/codex/config.toml` 或 `~/.codex/config.toml` |
| Windows | `%LOCALAPPDATA%\OpenAI\Codex\config\config.toml` 或 `%HOME%\.codex\config.toml` |

### Profile 文件（V2）

- 格式：`$CODEX_HOME/<name>.config.toml`（如 `~/.codex/work.config.toml`）
- 名称规则：仅允许 ASCII 字母数字、下划线、连字符（不含路径分隔符）

---

## 二、认证方式（Auth Layer）

### 1. ChatGPT 账号登录（推荐）

```bash
codex auth login
# 选择 "Sign in with ChatGPT"，通过浏览器 OAuth 完成
```

- 凭据存储位置由 `cli_auth_credentials_store` 控制：
  - `file`（默认）：`$CODEX_HOME/auth.json`
  - `keyring`：操作系统钥匙串
  - `auto`：有钥匙串则用钥匙串，否则回退 file
  - `ephemeral`：仅内存，进程结束即销毁

### 2. API Key 直接认证

```toml
# 在 config.toml 中不填，改用环境变量
```

| 环境变量 | 说明 |
|----------|------|
| `OPENAI_API_KEY` | OpenAI API 密钥 |
| `OPENAI_ORG_ID` | 组织 ID（计费归属） |
| `OPENAI_PROJECT_ID` | 项目 ID（计费归属） |

### 3. 自定义后端 / Azure

```toml
openai_base_url = "https://your-endpoint.openai.azure.com"
```

| 环境变量 | 说明 |
|----------|------|
| `OPENAI_BASE_URL` | 覆盖默认 API 基础地址 |

---

## 三、`config.toml` 完整顶层字段参考

以下字段均属于 `ConfigToml` struct，全部可选（`Option<T>`），省略时采用内置默认值。

### 3.1 模型与推理

```toml
model = "gpt-5.2-codex"                         # 默认对话模型
review_model = "gpt-5.2-codex"                   # /review 功能使用的模型
model_provider = "openai"                        # model_providers 映射中的键
model_context_window = 128000                    # 上下文窗口 token 数（整数）
model_auto_compact_token_limit = 64000           # 触发历史自动压缩的 token 阈值
model_auto_compact_token_limit_scope = "total" # "total" 或 "body_after_prefix"

model_reasoning_effort = "medium"                # "low" | "medium" | "high"
plan_mode_reasoning_effort = "medium"            # Plan 模式下的 reasoning effort
model_reasoning_summary = "auto"                 # "auto" | "concise" | "detailed" | "none"
model_verbosity = "medium"                       # GPT-5 输出控制: "low" | "medium" | "high"
model_supports_reasoning_summaries = false       # 强制开启 reasoning summary（覆盖模型目录）

model_catalog_json = "/path/to/models.json"      # 启动时加载的 JSON 模型目录
model_instructions_file = "/path/to/instructions.md"  # **不推荐**：覆盖内置模型指令
compact_prompt = "..."                           # 历史压缩时使用的自定义 prompt
personality = "friendly"                         # "none" | "friendly" | "pragmatic"
oss_provider = "ollama"                          # 本地模型后端: "lmstudio" | "ollama"
```

### 3.2 审批与权限

```toml
approval_policy = "smart"                        # 命令执行审批策略，见下方枚举
approvals_reviewer = "user"                      # 审批升级后由谁处理: "user" | "auto_review" | "guardian_subagent"

[auto_review]                                     # 自动审批子代理的策略
policy = "Additional instructions for the guardian subagent..."

[sandbox_mode]                                    # 沙箱模式（三层）
# "read-only"           # 仅读取，不写入
# "workspace-write"     # 工作区内可写（默认推荐）
# "danger-full-access"  # 完全访问，无沙箱

[sandbox_workspace_write]                         # 当 sandbox = "workspace-write" 时生效
writable_roots = ["/home/user/projects"]
network_access = true
exclude_tmpdir_env_var = false
exclude_slash_tmp = false

default_permissions = ":read-only"                # 默认权限 profile，冒号开头为内置，否则查 [permissions]

[permissions]
[permissions.my-profile]
description = "Custom profile"
extends = ":read-only"                            # 继承内置或自定义 profile
workspace_roots = { "/home/user/code" = true }
[permissions.my-profile.filesystem]               # 见 3.6 文件系统权限
[permissions.my-profile.network]                  # 见 3.6 网络权限
```

### 3.3 沙箱与执行环境

```toml
allow_login_shell = true                          # 是否允许模型请求登录 shell（默认 true）

[shell_environment_policy]
inherit = "all"                                   # "all" | "core" | "none"
ignore_default_excludes = true                    # 忽略 KEY/SECRET/TOKEN 等默认排除
exclude = ["PRIVATE_*", "AWS_*"]                  # 正则列表：排除的环境变量
set = { MY_VAR = "value" }                        # 强制注入的环境变量
include_only = ["PATH", "HOME", "USER"]           # 仅保留列表中的环境变量（正则）
experimental_use_profile = false                  # 使用 shell profile 启动命令
```

### 3.4 网络与代理

```toml
[network]                                         # 此节属于 permissions profile 内部；详见 3.6
```

### 3.5 MCP 服务器配置

```toml
[mcp_servers.my-mcp]
# stdio 传输
type = "stdio"  # 隐式通过 presence of `command`
command = "npx"
args = ["-y", "@modelcontextprotocol/server-filesystem", "/Users/user"]
env = { NODE_ENV = "production" }
env_vars = ["PATH", { name = "SECRET", source = "local" }]
cwd = "/home/user"

# streamable_http 传输（二选一）
url = "https://mcp.example.com/v1"
bearer_token_env_var = "MY_MCP_TOKEN"
http_headers = { "X-Custom" = "value" }
env_http_headers = { "Authorization" = "AUTH_ENV_VAR" }

# 通用设置
environment_id = "local"                          # 默认 "local"；远程环境需自定义
enabled = true
required = false
supports_parallel_tool_calls = false
startup_timeout_sec = 30                            # MCP 启动超时（秒）
tool_timeout_sec = 30                               # MCP 工具调用超时（秒）
default_tools_approval_mode = "auto"                # "auto" | "prompt" | "approve"
enabled_tools = ["readFile", "listDirectory"]       # 白名单
disabled_tools = ["deleteFile"]                     # 黑名单
scopes = ["read", "write"]                         # OAuth scope
oauth = { client_id = "my-client-id" }
oauth_resource = "resource-id"

[mcp_servers.my-mcp.tools.readFile]
approval_mode = "prompt"
```

### 3.6 权限 Profile 详细字段

```toml
[permissions.custom-profile]
description = "My custom permissions"
extends = ":workspace-write"                      # 可继承其他 profile

[permissions.custom-profile.workspace_roots]
"/home/user/project" = true
"/tmp" = false

[permissions.custom-profile.filesystem]
glob_scan_max_depth = 10
"/path/to/file" = "read"                          # "read" | "write" | "full"
"/path/to/dir/*.txt" = { "*.md" = "read", "*.tmp" = "write" }  # 作用域权限

[permissions.custom-profile.network]
enabled = true
proxy_url = "http://proxy:8080"
enable_socks5 = false
socks_url = "socks5://proxy:1080"
enable_socks5_udp = false
allow_upstream_proxy = false
dangerously_allow_non_loopback_proxy = false
dangerously_allow_all_unix_sockets = false
mode = "limited"                                    # "limited" | "full"
allow_local_binding = true

[permissions.custom-profile.network.domains]
"*.openai.com" = "allow"
"*.evil.com" = "deny"

[permissions.custom-profile.network.unix_sockets]
"/var/run/docker.sock" = "allow"

[permissions.custom-profile.network.mitm.hooks.my-hook]
host = "api.example.com"
methods = ["GET", "POST"]
path_prefixes = ["/v1/"]
query = { "debug" = ["true"] }
headers = { "X-Test" = ["abc"] }
body = { ... }                                      # 匹配请求体
type = "command"                                    # 触发动作
type = "command"                                    #     → Command { command, ... }
                                                    #     → Prompt   {} 暂停等待用户
                                                    #     → Agent    {} 子代理处理
action = ["strip-headers", "inject-token"]

[permissions.custom-profile.network.mitm.actions.inject-token]
strip_request_headers = ["X-Old-Auth"]
inject_request_headers = [
  { name = "Authorization", secret_env_var = "API_TOKEN", prefix = "Bearer " }
]
```

### 3.7 模型提供商自定义

```toml
[model_providers.openai-custom]
name = "My Custom OpenAI Endpoint"
base_url = "https://custom.openai.example.com"

[model_providers.bedrock]
# id 必须是 "amazon_bedrock"，内置保留，不可自定义但可补充配置

[model_providers.local-ollama]
name = "Local Ollama"
base_url = "http://localhost:11434"
```

Provider 的 `auth` 字段支持命令式 Token 获取：

```toml
[model_providers.my-provider.auth]
command = "aws"
args = ["sso", "get-access-token"]
timeout_ms = 5000
refresh_interval_ms = 300000
cwd = "/home/user"
```

### 3.8 Agent 线程控制

```toml
[agents]
max_threads = 10                                   # 并发 agent 线程上限
max_depth = 3                                      # 嵌套 agent 最大深度
job_max_runtime_seconds = 300                      # agent 作业超时
interrupt_message = true                           # agent 中断时记录模型可见消息

[agents.researcher]                                # 自定义角色
description = "Research-focused role"
config_file = "./agents/researcher.toml"
nickname_candidates = ["Herodotus", "Ibn Battuta"]
```

### 3.9 项目信任表

```toml
[projects]
"/home/user/company-repo" = { trust_level = "trusted" }
"/tmp/untrusted-clone" = { trust_level = "untrusted" }
```

### 3.10 历史记录

```toml
[history]
persistence = "save-all"                           # "save-all" | "none"
max_bytes = 10485760                               # 历史文件最大字节，超限时删除旧条目
```

### 3.11 分析与反馈

```toml
[analytics]
enabled = true

[feedback]
enabled = true
```

### 3.12 TUI 设置

```toml
[tui]
animations = true
show_tooltips = true
vim_mode_default = false
raw_output_mode = false
alternate_screen = "auto"                         # "auto" | "always" | "never"
status_line = ["model-with-reasoning", "current-dir"]
status_line_use_colors = true
terminal_title = ["activity", "project"]
theme = "solarized-dark"
pet = "cat"
pet_anchor = "composer"                           # "composer" | "screen-bottom"
session_picker_view = "dense"                       # "comfortable" | "dense"
terminal_resize_reflow_max_rows = 1000

[tui.notification_settings]
notifications = true                                # 或具体 command 列表: ["/usr/local/bin/notify"]
notification_method = "auto"                        # "auto" | "osc9" | "bel"
notification_condition = "unfocused"                # "unfocused" | "always"

[tui.keymap.global]
# 键绑定覆盖（见源码 tui_keymap.rs，此处略）

[tui.model_availability_nux]
# 记录各模型已展示 NUX 次数
gpt-5.2-codex = 1
```

### 3.13 通知与提醒

```toml
notify = ["/usr/local/bin/notify-send", "Codex Alert"]

[notice]
hide_full_access_warning = false
hide_world_writable_warning = false
fast_default_opt_out = false
hide_rate_limit_model_nudge = false
hide_gpt5_1_migration_prompt = false
hide_gpt_5_1_codex_max_migration_prompt = false
```

### 3.14 内存（Memories）

```toml
[memories]
disable_on_external_context = false                # MCP/WebSearch 时标记 memory 为 "polluted"
generate_memories = true
use_memories = true
dedicated_tools = false
max_raw_memories_for_consolidation = 256           # 1 ~ 4096
max_unused_days = 30
max_rollout_age_days = 10
max_rollouts_per_startup = 2                       # 1 ~ 128
min_rollout_idle_hours = 6                         # 1 ~ 48
min_rate_limit_remaining_percent = 25              # 0 ~ 100
extract_model = "gpt-4o-mini"                      # 摘要提取模型
consolidation_model = "gpt-4o"                       # 记忆整合模型
```

### 3.15 Web Search 工具

```toml
web_search = "cached"                              # "disabled" | "cached" | "live"

[tools.web_search]
context_size = "medium"                            # "low" | "medium" | "high"
allowed_domains = ["openai.com", "arxiv.org"]
location = { country = "US", region = "CA", city = "San Francisco", timezone = "America/Los_Angeles" }
```

### 3.16 生命周期 Hooks

```toml
[hooks]
[hooks.state.my-hook]
enabled = true
trusted_hash = "abc123..."

[hooks.PreToolUse]
[[hooks.PreToolUse]]
matcher = "shell"
[[hooks.PreToolUse.hooks]]
type = "command"
command = "echo 'About to run: {tool}'"
command_windows = "cmd /c echo About to run: {tool}"
timeout = 30
async = false
status_message = "Running pre-hook..."
```

支持的事件：`PreToolUse`, `PermissionRequest`, `PostToolUse`, `PreCompact`, `PostCompact`, `SessionStart`, `UserPromptSubmit`, `SubagentStart`, `SubagentStop`, `Stop`。

### 3.17 插件与市场

```toml
[plugins.my-plugin]
enabled = true
[plugins.my-plugin.mcp_servers.server1]
enabled = true
default_tools_approval_mode = "auto"
enabled_tools = ["readFile"]
disabled_tools = ["deleteFile"]
[plugins.my-plugin.mcp_servers.server1.tools.readFile]
approval_mode = "prompt"

[marketplaces.internal-marketplace]
last_updated = "2025-05-01T00:00:00Z"
last_revision = "abc123"
source_type = "git"                                # "git" | "local"
source = "https://github.com/openai/marketplace.git"
ref = "main"
sparse_paths = ["/skills"]
```

### 3.18 特性开关（Features）

```toml
[features]
# 以实际支持的 feature 键为准；未知键会被拒绝
some_feature = true
```

### 3.19 OTEL 可观测性

```toml
[otel]
log_user_prompt = false
environment = "dev"

[otel.exporter]                                     # exporter | trace_exporter | metrics_exporter
# type = "none"
# type = "statsig"
# type = "otlp-http"
#   endpoint = "https://otel.example.com"
#   headers = { "X-API-Key" = "secret" }
#   protocol = "binary"   # "binary" | "json"
#   tls = { ca_certificate = "...", client_certificate = "...", client_private_key = "..." }
# type = "otlp-grpc"
#   ... 同上，协议为 grpc

span_attributes = { service = "codex", team = "ai" }
tracestate = { myvendor = { key = "value" } }
```

### 3.20 Windows 专属

```toml
[windows]
sandbox = "elevated"                                # "elevated" | "unelevated"
sandbox_private_desktop = true
```

### 3.21 实时语音（Experimental / 实验性）

```toml
[audio]
microphone = "Built-in Microphone"
speaker = "Built-in Output"

[realtime]
version = "v2"                                      # "v1" | "v2"
type = "conversational"                             # "conversational" | "transcription"
transport = "webrtc"                                # "webrtc" | "websocket"
voice = "alloy"
```

### 3.22 其他杂项

```toml
instructions = "全局系统指令"
developer_instructions = "附加的 developer 角色消息"

include_permissions_instructions = true
include_apps_instructions = true
include_collaboration_mode_instructions = true
include_environment_context = true

project_doc_max_bytes = 32768                     # AGENTS.md 最大读取字节
project_doc_fallback_filenames = []                 # AGENTS.md 缺失时的回退文件名列表
project_root_markers = [".git", ".codex"]           # 项目根目录检测标记

tool_output_token_limit = 8192                      # 工具输出存储到上下文时的 token 预算
background_terminal_max_timeout = 300000            # write_stdin 后台轮询超时（ms）

sqlite_home = "/home/user/.codex"                   # SQLite 状态数据库目录
log_dir = "/home/user/.codex/log"                   # 日志目录（显式设置后启用 TUI 文本日志）
file_opener = "vscode"                              # "vscode" | "vscode-insiders" | "windsurf" | "cursor" | "none"

hide_agent_reasoning = false
show_raw_agent_reasoning = false

service_tier = "default"                            # "default" | "priority"（旧 "fast"）| "flex"
chatgpt_base_url = "https://chatgpt.com"            # ChatGPT 后端地址
apps_mcp_product_sku = "sku-123"                    # Codex Apps MCP 请求携带的 SKU

forced_chatgpt_workspace_id = ["uuid1", "uuid2"]    # 限制仅能登录指定 workspace
forced_login_method = "chatgpt"                     # "chatgpt" | "api"

check_for_update_on_startup = true
disable_paste_burst = false

suppress_unstable_features_warning = false

# Experimental，不推荐生产使用
experimental_compact_prompt_file = "/path/to/compact.md"
experimental_use_unified_exec_tool = false
experimental_realtime_ws_base_url = "wss://..."
experimental_realtime_ws_model = "gpt-4o-realtime"
experimental_thread_config_endpoint = "https://config.example.com"
```

---

## 四、枚举类型速查

### 4.1 `AskForApproval`（命令审批策略）

| 值 | 含义 |
|----|------|
| `never` | 不审批，直接执行 |
| `auto` | 智能自动审批 |
| `edits` | 文件编辑类需审批 |
| `full` | 所有命令都需审批 |
| `always` | 永远需审批 |

### 4.2 `AppToolApproval`（工具审批模式）

| 值 | 含义 |
|----|------|
| `auto` | 自动执行 |
| `prompt` | 提示用户确认 |
| `approve` | 需要显式批准 |

### 4.3 `SandboxMode`

| 值 | 含义 |
|----|------|
| `read-only` | 只读 |
| `workspace-write` | 工作区可写 |
| `danger-full-access` | 完全访问，无沙箱 |

### 4.4 `TrustLevel`

| 值 | 效果 |
|----|------|
| `trusted` | 信任项目，默认 workspace-write |
| `untrusted` | 不信任，默认 read-only |

### 4.5 `AuthCredentialsStoreMode`

| 值 | 说明 |
|----|------|
| `file` | `$CODEX_HOME/auth.json` |
| `keyring` | OS 钥匙串 |
| `auto` | 优先 keyring |
| `ephemeral` | 仅内存 |

### 4.6 `AltScreenMode`

| 值 | 说明 |
|----|------|
| `auto` | 使用 alternate screen（默认） |
| `always` | 始终使用 |
| `never` | 内联模式，保留滚动历史 |

### 4.7 `ModeKind`（协作模式）

| 值 | 说明 |
|----|------|
| `plan` | Plan 模式 |
| `default` | 默认模式（含旧别名 `code`, `execute`, `custom`, `pair_programming`） |

### 4.8 `HistoryPersistence`

| 值 | 说明 |
|----|------|
| `save-all` | 全量保存 |
| `none` | 不写入磁盘 |

### 4.9 `McpServerTransportConfig`

两种互斥形态：

**stdio**（本地命令）：`command`, `args`, `env`, `env_vars`, `cwd`
**streamable_http**（HTTP 端点）：`url`, `bearer_token_env_var`, `http_headers`, `env_http_headers`

### 4.10 `NotificationMethod`

| 值 | 说明 |
|----|------|
| `auto` | 自动检测 |
| `osc9` | OSC 9 序列 |
| `bel` | BEL 字符提示 |

### 4.11 `NotificationCondition`

| 值 | 说明 |
|----|------|
| `unfocused` | 仅终端失焦时通知 |
| `always` | 总是通知 |

### 4.12 `RealtimeTransport`

| 值 | 说明 |
|----|------|
| `webrtc` | 默认 |
| `websocket` | websocket 回退 |

### 4.13 `SessionPickerViewMode`

| 值 | 说明 |
|----|------|
| `comfortable` | 舒适布局 |
| `dense` | 紧凑布局 |

### 4.14 `ServiceTier`

| 内部值 | API 请求值 |
|--------|-----------|
| `Fast` | `priority` |
| `Flex` | `flex` |

---

## 五、环境变量汇总

| 变量 | 影响范围 | 说明 |
|------|---------|------|
| `OPENAI_API_KEY` | 全局认证 | API 密钥（当 ChatGPT OAuth 不可用时回退） |
| `OPENAI_ORG_ID` | 全局认证 | 组织 ID |
| `OPENAI_PROJECT_ID` | 全局认证 | 项目 ID |
| `OPENAI_BASE_URL` | 全局 | 覆盖默认 API 基础 URL |
| `CODEX_HOME` | 全局路径 | 覆盖 `~/.codex` 主目录 |
| `CODEX_SQLITE_HOME` | 全局路径 | SQLite DB 目录（默认使用 `CODEX_HOME`） |
| `CODEX_CONFIG_PATH` | 全局路径 | 覆盖用户级 `config.toml` 路径 |
| `DISABLE_TELEMETRY` | 全局 | `1` 禁用遥测 |
| `CODEX_DEBUG` | 全局 | `1` 启用调试日志 |
| `CODEX_MANAGED_BY_NPM` / `CODEX_MANAGED_BY_BUN` | 内部 | 包管理器标记（由启动器注入） |

---

## 六、源码 / JSON Schema 引用

若需追踪新增字段，查看以下文件：

1. **主配置结构**：`codex-rs/config/src/config_toml.rs` → `ConfigToml`
2. **类型枚举**：`codex-rs/config/src/types.rs`、`codex-rs/protocol/src/config_types.rs`
3. **权限配置**：`codex-rs/config/src/permissions_toml.rs`
4. **Profile 定义**：`codex-rs/config/src/profile_toml.rs`
5. **MCP 配置**：`codex-rs/config/src/mcp_types.rs`
6. **Hooks**：`codex-rs/config/src/hook_config.rs`
7. **加载器**：`codex-rs/config/src/loader/mod.rs`（层级合并逻辑）

---

**版本对应**：本文基于 `@openai/codex@0.135.0` / `openai/codex` repo `main` 分支（2025-05 状态）。后续版本可能新增字段，请以源码 `ConfigToml` struct 及官方 `config-reference` 文档为准。
