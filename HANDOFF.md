# Handoff Summary — FreeModelMenuBar ux 优化（rebuild 分支）

## 1. 当前进度

### 累计 commit（`rebuild` 分支，HEAD = `346f32f`）
| Commit | 改动 |
|---|---|
| `df68112` | chore: 初始快照 - 导入 FreeModelMenuBar 源码 + Codex 配置文档 |
| `1100746` | 账号 / Codex 注入 头部同构（统一 +/− 按钮） |
| `54bbe73` | 详情区两处优化（重命名按钮 / 激活按钮移到底栏） |
| `846d8e7` | 抽出 `SidebarRow` 组件，三处侧边栏行共用 |
| `fa07377` | 顶栏副标题 + logsHeader 同构 + 路由校验辅助 |
| `0aafca2` | routerSection 4 个 TextField 加红边 |
| `d3b0ecd` | 内联添加行互斥 + emptyState 移除重复按钮 |
| `11ecf8b` | 抽 `routerStatusColor` 公共方法，4 处统一状态点颜色 |
| `63c644b` | 注入详情"恢复默认" + 右键二次确认 + 日志区合并 + 切账号重置 |
| `eb56d2e` | 详情区/添加行布局 + 必填提示 + undo + 字符数 |
| `a2223bd` | logsHeader 三段式 + API Key spinner 内嵌 + queryMode 切换动画 + 恢复默认按钮角色调整 |
| `a798986` | 侧栏选中态高亮 + testResult 切换淡入动画 |
| `04b3087` | 账号余额三元组 + isLow 警示 + router 表单带星提示拆分 |
| `82aa926` | 详情区 3 段 DisclosureGroup + routerSection toggle 缺 API Key 文案 + 保存按钮换行 |
| `f8e42c4` | MenuContent "7天窗口重置" → "过期时间" |
| `62546ea` | MenuContent 标题栏加副标题 v1 · N 个账号 |
| `61e41ae` | refactor: 抽 3 个侧边栏 Section 为独立 var (C2 step 1) |
| `346f32f` | refactor: 抽 accountListRow / codexConfigListRow 2 个 helper (C2 step 2) |

### 正在做（C2 三步小步快跑的 step 3 —— **未开始**）

工作区已重置到 `346f32f` HEAD，`git status` 干净（除 untracked `build_manual/`）。

- ✅ step 1 (`61e41ae`)：抽 `accountsSection / codexSection / logsSection` 3 个独立 `var`
- ✅ step 2 (`346f32f`)：抽 `accountListRow(_:)` / `codexConfigListRow(_:)` 2 个 row helper（contextMenu 移入 helper）
- ⚠️ step 3 — 拆成 **2 个 commit**（小步快跑再小步）：
  - **3a**：加 2 个 @State（`pendingRenameAccount` / `renameInput`）+ contextMenu 内"重命名…"Button
  - **3b**：accountList 末尾加 `.alert` 重命名弹窗

## 2. 关键决策与约束

### 代码风格（最关键）
- **绝不用行号索引**做多步修改——一旦某步改了 lines 长度，后续 step 索引全错。**改用 `text.replace(old_block, new_block)` 字符串唯一匹配**。
- SettingsView.swift 之前 awk 处理过，**`// MARK: -` 注释里中文之间有 `**` 字符**（不是 `// MARK:` 字符），不要用 `awk` 全文替换。
- SettingsView struct 闭 `}` 行号是动态的，定位靠 `grep -n "^}$"` 或 `grep -n "MARK:.*账号"`。

### 编译验证
- 命令：
  ```sh
  P="/Users/yyq/Documents/Rebuild Bar/FreeModelMenuBar/FreeModelMenuBar"
  awk -v p="$P" '{print p"/"$0}' FreeModelMenuBar/build_manual/all2.swift | tr '\n' '\0' > /tmp/sources.bin
  xargs -0 swiftc -target arm64-apple-macos13.0 < /tmp/sources.bin \
      -o "/Users/yyq/Desktop/FreeModelMenuBar.app/Contents/MacOS/FreeModelMenuBar"
  ```
- **不需要重启 app**（用户明确说"编译通过即目标完成"）
- **不 codesign**

### C2 上一轮 type-check 死锁教训
- 一次性改 5 处（state + contextMenu + alert + 抽 section + 抽 helper + 抽 message 常量）→ SwiftUI `List { Section { ... } }` type-check 死锁
- **解决方案**= 三步小步快跑：step 1 抽 section → step 2 抽 row helper → step 3 加 state + alert。每步小且可 revert。

### 用户偏好
- 中文界面；细节挑剔
- macOS 27 internal, arm64, SDK 26.5，必须 `-target arm64-apple-macos13.0`
- 编译通过即任务完成

## 3. C2 step 3 接下来要做（**清晰的下一步**）

### 3a commit: 加 2 个 @State + contextMenu "重命名…"
- 位置 1: line 45-46 之后插 2 个 `@State`:
  ```swift
  // 重命名
  @State private var pendingRenameAccount: ProviderAccount? = nil
  @State private var renameInput: String = ""
  ```
- 位置 2: `accountListRow` 内 contextMenu 现有 `删除账号` Button **之前**加 1 个 Button:
  ```swift
  Button {
      pendingRenameAccount = account
      renameInput = account.displayName
  } label: {
      Label("重命名…", systemImage: "pencil")
  }
  ```

### 3b commit: accountList 末尾加 `.alert`
- 位置: accountList var 末尾（line 232 之后），第二个 `.confirmationDialog` 之后：
  ```swift
  .alert("重命名账号", isPresented: Binding(
      get: { pendingRenameAccount != nil },
      set: { if !$0 { pendingRenameAccount = nil; renameInput = "" } }
  ), presenting: pendingRenameAccount) { acct in
      TextField("账号名称", text: $renameInput)
      Button("重命名") {
          let trimmed = renameInput.trimmingCharacters(in: .whitespacesAndNewlines)
          if !trimmed.isEmpty {
              accountManager.renameAccount(id: acct.id, displayName: trimmed)
              balanceManager.syncFromActiveAccount()
          }
          pendingRenameAccount = nil
          renameInput = ""
      }
      Button("取消", role: .cancel) {
          pendingRenameAccount = nil
          renameInput = ""
      }
  } message: { _ in
      Text("修改后立即在侧栏生效。")
  }
  ```
- **注意 macOS 13 不支持 `.textInputAutocapitalization`**，删除该 modifier。
- 如果 type-check 又死锁，把整个 alert 抽成独立 `var renameAccountAlert: some View` + 在 accountList 内 `renameAccountAlert` 引用（参考 `deleteAccountDialog` 模式）。

### 3a 验证 → commit
### 3b 验证 → commit

## 4. 关键文件 / 行号（当前 HEAD 状态）

- `FreeModelMenuBar/FreeModelMenuBar/SettingsView.swift` (1610 行)
- `FreeModelMenuBar/FreeModelMenuBar/CodexInjectionSettingsView.swift` (267 行)
- `FreeModelMenuBar/FreeModelMenuBar/MenuContent.swift` (438 行)

| 位置 | 行号 | 说明 |
|---|---|---|
| `pendingDeleteAccount / pendingDeleteCodexConfig` 声明 | 45-46 | 后面插 2 个 @State（步骤 3a） |
| `accountListRow(_:)` | 276-286 | contextMenu 内加"重命名…"Button（步骤 3a） |
| accountList var 末尾（line 232 `}` 之后） | 232+ | 加 `.alert`（步骤 3b） |
| `routerStatusColor` 公共方法 | 1488 | 已 commit |
| `accountsSectionHeader: some View` | 288 | MARK 锚点 |
| `codexConfigListRow(_:)` | 288+ | 已 commit |

## 5. 风险点

- **不要用 Python list index 做多步**——上一轮已踩坑。
- **步骤 3b 的 `.alert` 可能再次 type-check 死锁**——fallback 是抽 `renameAccountAlert` 独立 var。
- **`.textInputAutocapitalization` 不存在**于 macOS 13，删掉即可。

## 6. 剩余重要项（C2 完成后）

- **C3 Codex 注入测试按钮**（调一次 `/v1/models` 验证 auth.json）——独立 1 轮
- **D18 MenuContent 路由按钮样式**（`.plain` 改 `.bordered` + `.tint`）——独立 1 轮
- **D19 CodexInjectionSettingsView 按钮高度对齐**（"激活此配置" `.borderedProminent` vs "恢复默认" `.bordered`）——独立 1 轮
- **D14 MenuContent 复用 routerStatusColor**（6 轮前抽出的公共方法 MenuContent 没用到）——独立 1 轮
- **D12 注入"已自动保存"反馈**（Date 格式化 helper）——独立 1 轮
