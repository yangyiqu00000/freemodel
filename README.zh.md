<div align="center">

# 💲 FreeModel MenuBar

**一个轻量级的 macOS 菜单栏小工具，解决三大痛点。**

> 告别手改 `~/.codex/config.toml`,告别余额焦虑,告别切换账号就要重启 Codex。

[English](README.md) · [中文](README.zh.md)

[![macOS](https://img.shields.io/badge/macOS-13%2B-blue?logo=apple)](#-系统要求)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange?logo=swift)](#-技术栈)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Release](https://img.shields.io/github/v/release/yangyiqu00000/freemodel)](https://github.com/yangyiqu00000/freemodel/releases)
[![Stars](https://img.shields.io/github/stars/yangyiqu00000/freemodel?style=social)](https://github.com/yangyiqu00000/freemodel)

[⬇️ 下载 v0.0.3](https://github.com/yangyiqu00000/freemodel/releases/latest) · [🐛 反馈问题](https://github.com/yangyiqu00000/freemodel/issues)

</div>

---

## ✨ 为什么需要 FreeModel MenuBar?

如果你用 [OpenAI Codex](https://github.com/openai/codex) 但不是用的官方 OpenAI 入口,大概率经历过这个循环:

```text
vim ~/.codex/config.toml   # 改 provider、贴 key、换 base_url
codex                      # 重启
# 测试一下
vim ~/.codex/config.toml   # 再改一次
codex                      # 再重启
# …… 那还剩多少余额? 不知道。
```

**FreeModel MenuBar 把这一整套仪式压缩成菜单栏里的一次点击。**

它刻意做得小。不是代理管理器,不是 IDE,不是 CLI 替代品。
它是一个**专门给 Codex 用的菜单栏切换台**——三件事,做好就行。

---

## 🎯 三大特点

### 1. 🌐 统一所有协议为 Responses

Codex 走的是 **OpenAI Responses** 协议,而绝大多数第三方服务只支持 **Chat Completions**(或者各自的私有协议)。

本应用内置了一个极小的本地路由,会**透明地把任何协议翻译成 Responses**。添加一个 Provider、配好它真实的 base URL,剩下的事路由全部帮你搞定。

由此带来的一个"魔法":在 `~/.codex/config.toml` 里,你只需要写**一个** `base_url`,而且永远不变:

```toml
base_url = "http://127.0.0.1:7842/v1"
```

就这样。再也不变。就算你从 DeepSeek 切到 OpenRouter 再切到某个野鸡中转,**Codex 看到的 URL 始终是这一个。**

> 🪄 一次配置,菜单栏点点点,终身受用。

### 2. 🔁 热切换账号,不用重启 Codex

点一下 💲 图标 → 选个账号 → **实时切换完毕。**

- 路由实时加载新的上游配置
- Codex 保持原有流式响应不中断
- 不用 `killall codex`,不用重启,不会丢上下文

这才是核心。以前的痛苦在于 `config.toml` 是事实唯一来源,换 key 必须重启。
现在本地路由作为稳定中间层,**Codex 跟具体的 Provider 完全解耦。**

> 🧘 连续测试三家服务商,工作流不会断。

### 3. 💰 菜单栏直接看余额,告别焦虑

不用再登网页控制台。不用再猜"还剩 5 美元还是 0.5 美元"。

- 🟢 健康 / 🟠 偏低 / 🔴 告急 — 一眼可见的颜色编码
- 每个 Provider 可单独设置告警阈值
- 按你设定的频率自动刷新
- 点菜单栏图标,看每个账号的明细

路由是本地的,但**余额查询**会调每个服务商的 billing 接口(对没有 billing 接口的 Provider,会用隔离的 WebKit 窗口抓取控制台——你的 Key 全程不离开本机)。

> 😌 告别"还够用吗"的内耗。

---

## 🧩 三类配置场景,覆盖所有 Codex 用法

本应用不追求"大而全",只支持**三种模式**,合起来覆盖所有人用 Codex 的姿势:

| 模式 | 适用场景 | `config.toml` 里的 `base_url` | 路由是否运行 |
|---|---|---|---|
| **A. 第三方 + Responses 转换** | 用 DeepSeek / OpenRouter / ModelScope / 任何只支持 Chat Completions 的服务商 | `http://127.0.0.1:<port>/v1` | ✅ 开启 |
| **B. 第三方,原生 Responses** | 服务商本身已经原生支持 Responses | `http://127.0.0.1:<port>/v1` | ⚪ 可选透传 |
| **C. 官方 OpenAI** | 直接用 OpenAI | 官方的 `https://api.openai.com/v1` | ❌ 不需要,直接读 config |

**就这三种。** 任意时刻只可能处于其中一种,点一下就能切换。

> 路由是"按需"的:不需要协议转换就别开。菜单栏应用本体可以独立工作,直接读 `~/.codex/config.toml` 里的官方配置,只展示余额,无需路由,无需 Node,没有额外进程。

---

## 🚀 90 秒快速上手

```text
   ┌──────────────────────────────────────────────────────────────┐
   │  1. 安装 FreeModelMenuBar(DMG,拖到 /Applications)            │
   │  2. 点菜单栏 💲 → 设置                                         │
   │  3. 添加一个账号(粘贴 API Key,选服务商)                        │
   │  4. 选你属于哪一类:                                             │
   │       A) 第三方 → 路由 ON  → 完成                              │
   │       B) 第三方原生 → 路由透传 → 完成                          │
   │       C) 官方 OpenAI  → 无路由,只展示余额                     │
   │  5. 在 Codex config.toml 里,把 base_url 改成                 │
   │       http://127.0.0.1:<port>/v1   (一次,永不变)              │
   │  6. 以后:点 💲 → 切账号 → 直接用                                │
   └──────────────────────────────────────────────────────────────┘
```

第 5 步之后,`config.toml` 再也不用动了。

---

## 📦 安装

### 方式 A:下载 DMG(推荐)

1. 前往 [**Releases → v0.0.3**](https://github.com/yangyiqu00000/freemodel/releases/latest)
2. 下载 `FreeModelMenuBar-0.0.3.dmg`
3. 打开,把 app 拖进 `/Applications`
4. 启动 — 菜单栏里找 💲

> **首次启动提示:** 如果 macOS Gatekeeper 弹窗警告,Finder 里右键 app → **打开** → 再次点 **打开**。对 ad-hoc 签名 app 来说只需做这一次。

### 方式 B:自己编译

```bash
git clone https://github.com/yangyiqu00000/freemodel.git
cd freemodel/FreeModelMenuBar
./build.sh
```

脚本会自动编译、ad-hoc 签名、把最新的 `FreeModelMenuBar.app` 放到桌面。

**要求:** macOS 13+、Xcode 15+、Node 16+(只有**模式 A** 才需要,模式 B/C 都不依赖)。

---

## ❓ 常见问题

**Q:安全吗?你在替我改 `config.toml`?**
A: 应用只读写 `~/.codex/config.toml`,从不外发。唯一发起的网络请求都指向你显式添加的服务商。源码 100% Swift,欢迎审阅。

**Q:为什么需要本地路由?Codex 不能直接用对应的 base_url 吗?**
A: 两个原因:
   1. Codex 用 Responses,大多数服务商用 Chat Completions。路由在本地做协议桥接——没有第三方代理,除了你自己发起的那次上游请求,数据不离开本机。
   2. 解耦。路由作为稳定中间层,**Codex 完全不需要知道你在用哪家服务商。** 菜单栏切账号,路由切换上游,Codex 无感。

**Q:模式 A 适用于我常用的服务商 X 吗?**
A: 只要它支持 OpenAI Chat Completions(绝大多数都支持),就 OK。路由会做协议转换,再加一些体验优化:
   - `developer` 角色 → `system`(有些服务商会卡 `developer`)
   - 错误包装成 `event: response.failed` SSE
   - 你停止生成时立刻拆上游 TCP(防止 Token 偷偷跑掉)

**Q:我只用官方 OpenAI 呢?**
A: 用**模式 C**。菜单栏 app 直接读你现有的 `~/.codex/config.toml`,展示余额。没有路由,没有 Node,没有额外进程。

**Q:支持 Apple Silicon?Intel?**
A: 都支持。通用二进制(`x86_64 arm64`)。

**Q:能在 Cursor / Claude Code / Aider 里用吗?**
A: Cursor:可以,把它里面的 OpenAI base URL 指向本地路由就行。其它两个不用 Codex 的 Responses 协议,那"统一 base URL"的小技巧不适用——但**模式 C**(余额监控)照样能用。

**Q:为什么是 ad-hoc 签名?能公证吗?**
A: ad-hoc 适合个人使用和随便传传。Apple 公证需要 $99/年的开发者账号,有需求的话可以安排。

---

## 🧪 技术栈

| 层 | 选型 | 为什么 |
|---|---|---|
| UI | SwiftUI + `MenuBarExtra` | 原生,不上 Electron,二进制不到 10MB |
| 生命周期 | AppKit + `NSWorkspace` 通知 | 唤醒自愈 |
| 存储 | macOS Keychain | Key 永远不落盘明文 |
| 路由 | Node.js (`node:http` / `node:https`) | 零依赖,支持多协议自动识别 |
| 进程模型 | `Process` + `readabilityHandler` | 干净退出,无僵尸端口 |

项目结构:

```text
FreeModelMenuBar/
├── FreeModelMenuBar/        # Swift 应用本体
│   ├── CodexInjector/       # Provider / Config / Auth 三层
│   │   ├── AuthLayer/       # Keychain + JSON 存储
│   │   ├── ConfigLayer/     # TOML 读写(无 TOMLKit 依赖)
│   │   └── ProviderLayer/   # 服务商目录与预设
│   ├── router_sidecar.js    # 本地 Responses ↔ Chat 路由
│   ├── MenuContent.swift    # 你看到的那个 💲 菜单
│   └── ...
├── scripts/                 # 路由的静态检查
├── docs/                    # 设计文档与实施方案
└── build.sh                 # 一键编译 → ad-hoc 签名 → 桌面
```

---

## 🗺️ 路线图

已经完成:

- [x] 多账号热切换,不重启 Codex
- [x] 三类配置场景(路由 / 透传 / 官方)
- [x] 本地 Responses ↔ Chat Completions 路由
- [x] 唤醒自愈
- [x] Keychain 凭据存储
- [x] 菜单栏余额监控,颜色分级告警
- [x] **Anthropic Messages 协议支持** — 路由新增 Responses → Anthropic Messages 翻译,
      兼容 Claude 类端点
- [x] **协议自动检测** — 路由根据 URL 后缀自动识别上游协议
      (`/v1/messages` → Anthropic, `/v1/chat/completions` → Chat)
- [x] **设置页拖拽排序** — 账号卡片支持拖拽调整顺序
- [x] **v0.0.3: 路由重构与加固**
  - 协议适配器注册制(`registerProtocol`) — 一行代码注册新协议
  - 55 个路由纯函数单元测试(<1s,零 HTTP)
  - `require()` 无副作用 — `require('./router_sidecar')` 不再启动服务器
  - `repairToolCallMessageOrder` 全局状态解耦
  - 所有魔数 → `CONFIG` 对象,可通过 `PROXY_*` 环境变量覆盖
  - 流式无数据超时(默认 60s,`PROXY_STREAM_TIMEOUT_MS`)
  - `reasoning_content` 跨轮保留
  - Anthropic `tool_use` → `tool_result` 邻接强制执行(合成缺失结果)

接下来:

- [ ] **分模式使用教程** — 首次运行时引导,逐步配置 A / B / C,配截图
- [ ] **支持更多第三方中转** 的服务商目录扩充
- [ ] **可配置的 API 用量刷新间隔** (按服务商)
- [ ] **账号级模型别名**(`/v1/models/gpt-4` → 上游的 `gpt-4-turbo`)
- [ ] **Token 用量分析** (近 7 / 30 天)
- [ ] Apple 公证版本(等开发者账号 — 见 FAQ)

欢迎 PR,欢迎 issue。如果你也觉得再也不用 `vim config.toml` 了,给个 ⭐ 吧。

---

## 🤝 参与贡献

```bash
git clone https://github.com/yangyiqu00000/freemodel.git
cd freemodel
git checkout -b feature/your-thing
# 开干
git commit -m "feat: your thing"
gh pr create
```

几点约定:

- **路由保持零依赖。** 这是 feature,不是偷懒。
- **零遥测。** 这是个本地工具,不要加非用户主动发起的网络请求。
- **SwiftUI 风格对齐** `MenuContent.swift` — 自动布局、语义化颜色、不写死 RGB。
- **给路由加新行为时,在 `scripts/` 加一个静态检查。** 那里的脚本是用来兜回归的。

详细设计文档见 [`FreeModelMenuBar/docs/`](FreeModelMenuBar/docs/)。

---

## 📄 许可证

[MIT](LICENSE) — 随便用,出问题别找我。

```
Copyright (c) 2026 yangyiqu00000
```

---

<div align="center">

**如果你也觉得再也不用 `vim config.toml` 了,给个 ⭐ 吧。**

用 ❤️ 和对菜单栏应用略显不健康的执念打造。

</div>
