# omni-free-llm —— 免费 AI 对话，跨平台一键安装

把 [oMNIROUTE](https://github.com/diegosouzapw/OmniRoute)（免费 MIT AI 网关）打包成**跨平台、交互式、零私钥、傻瓜式**的一键安装器。全新电脑也能装，装完终端直接免费对话，还能一键接入任意 OpenAI 兼容的编辑器 / CLI。

---

## 0. 小白起步（3 分钟）

无论哪个系统，只需三步：**解压 → 打开终端 → 把安装文件拖进终端回车**。全程不用记任何命令、不用 cd。

### Windows（最推荐：双击）

1. 解压 `omni-free-llm.zip`（右键 → 解压到当前文件夹），得到 `omni-free-llm` 文件夹。
2. 进入文件夹，**双击 `install.bat`**，窗口自动打开并开始安装，装完即用。

想用终端手动装的话：

1. 在 `omni-free-llm` 文件夹空白处 **Shift+右键 → 「在此处打开 PowerShell」**（⚠️ 是 PowerShell，不是 cmd）。
2. 输入 `powershell -ExecutionPolicy Bypass -File `（**末尾留一个空格**），然后**把 `install.ps1` 文件拖进窗口**（会自动填入完整路径），回车。

> ⚠️ **一定用 PowerShell，不要用 cmd！** 在 cmd 里跑 `powershell ...` 会报「'powershell' 不是内部或外部命令」。最省事的还是直接双击 `install.bat`。

### macOS（双击 `install.command`）

> ⚠️ **别双击 `install.bat`，也别双击 `install.sh`。** `.bat` 是 Windows 专用；`.sh` 在 macOS 上只会被文本编辑器（VS Code 等）打开，「打开方式」里**不会出现终端**——这是 macOS 的正常行为，不是坏了。Mac 能双击运行的扩展名是 `.command`。

**方式 A（推荐）：双击 `install.command`**，会自动打开终端并开始安装。

两种常见拦路提示，都能一步解决：

- 弹「**无法打开，因为它来自身份不明的开发者**」→ **右键点 `install.command` → 选「打开」→ 在弹窗里再点一次「打开」**。（只需做这一次）
- 报 `permission denied` → 解压时丢了可执行权限。打开终端，输入 `chmod +x `（**末尾留一个空格**）→ 把 `install.command` 拖进窗口 → 回车，然后再双击。

**方式 B（最稳，不依赖权限、不会被拦）**：

1. 解压 zip（双击自动解压）。
2. 打开 **终端**：启动台 → 其他 → 终端（或 Spotlight 搜 `Terminal`）。
3. 输入 `bash `（**末尾留一个空格**）→ **把 `install.sh` 拖进终端窗口**（自动填入完整路径）→ 回车。

### Linux / 国产 Linux（麒麟 / 统信 UOS / openEuler / Deepin）

1. 解压 zip（图形界面右键解压，或 `unzip omni-free-llm.zip`）。
2. 打开终端（通常 `Ctrl+Alt+T`）。
3. 输入 `bash `（**末尾留一个空格**）→ **把 `install.sh` 拖进终端窗口**（自动填入完整路径）→ 回车。

---

## 一、前置：全新电脑也能装

安装器会**自动检测你的操作系统**，没有 Node 会自动引导安装：

| 系统 | 入口 | Node 引导方式 |
|---|---|---|
| Windows（含华为/小米笔记本） | `install.bat`（最简单，双击） / `install.ps1` | winget 自动装 / 官网 |
| macOS | `install.command`（双击） / `install.sh` | Homebrew 自动装 / 官网 |
| Linux（Ubuntu/Debian） | `install.sh` | NodeSource 脚本自动装 |
| 国产 Linux（麒麟/统信 UOS/Deepin） | `install.sh` | apt 自动装 |
| 国产 Linux（openEuler/CentOS 等） | `install.sh` | dnf 自动装 |

## 二、一键安装

```bash
# Windows（最稳的方式是直接双击 install.bat；下面是手动敲的等价命令）
powershell -ExecutionPolicy Bypass -File install.ps1

# macOS（最稳的方式是直接双击 install.command；下面是手动敲的等价命令）
# Linux / 国产 Linux 也用这一条
bash install.sh
```

也可以直接 `node install.mjs`（已装 Node 时）。

安装是**交互式**的，按提示走：

1. **① 选择安装/存储文件夹**（回车用默认 `~/.omniroute`）
2. **② 选择免费来源**：
   - `1` 匿名免费池 —— 零注册即用
   - `2` 个人 API —— 稳定，需注册
   - `3` 两个都要（推荐）
3. 选 `2` 或 `3` 时，**一步步引导你注册每个免费 AI**，粘贴 key 即可，并提醒你**自己保存好 key**
4. **③ 是否启用「关终端自动关」看门狗**（按你的操作系统给方案）
5. **④ 是否启用 MCP**（让编辑器里的 AI 自助管理免费池）
6. **⑤ 接入编辑器**（终端默认直接可用）

## 三、匿名免费池 vs 个人 API（优缺点）

| | 匿名免费池 | 个人 API |
|---|---|---|
| 门槛 | 零注册，装完即用 | 花 1 分钟注册（无信用卡） |
| 稳定性 | ❌ 易限流、偏慢 | ✅ 稳定、额度明确 |
| 速度 | 一般 | ✅ 快（如 Groq LPU） |
| 模型 | 受限 | ✅ 更全、可指定 |
| 隐私 | 可能被记录 | 自己可控 |
| 国内直连 | 部分被墙 | ✅ 智谱/DeepSeek 国内直连免 VPN |

> **结论**：匿名池是「保底能跑」，个人 API 才是「长期稳定可用」。推荐选 `3`（两者都要），匿名池兜底 + 个人 API 主力。

## 四、日常使用

```bash
omni up                  # 只启动服务（chat 会自动启动，一般不用手敲）
omni chat                # 进入交互式 AI 会话（:q 或 Ctrl+C 退出，回答中也能退；:new 清空历史）
omni chat "你的问题"     # 单次提问（服务没起会自动启动）
omni memory              # 长记忆：列出已保存的对话片段
omni memory search <词>  # 按关键词检索历史对话
omni memory graph        # 输出记忆关系图（mermaid，可粘到任何支持的地方渲染）
omni key                 # 接入个人 key（先看优缺点）
omni free-list           # 自动检索最新免费 AI 清单（含注册链接）
omni status              # 状态 + 连接信息
omni editor              # 接入编辑器的连接信息
omni mcp                 # MCP 接入配置
omni down                # 关闭释放资源
```

### 对话体验

- **流式输出 + 思考动画**：回车后立刻显示「已收到，正在思考…」并转圈计时，第一个字返回就开始逐行输出。
- **彩色 Markdown**：小标题、**粗体**、`代码`、列表、代码块在终端里直接上色。
- **多轮上下文**：交互模式会带上对话历史（默认保留最近 20 轮），AI 记得上文。
- **耗时与用量**：每次回答后显示 `⏱ 耗时 · 模型 · 输入/输出 token`；上游不返回统计时退回显示字数。
- **断点接手**：上游额度耗尽或限流导致中途断线时，自动换源并把**已生成的半截内容**交给接手的模型续写，不会从头重来，模型栏会显示切换轨迹（如 `模型 A → B`）。
- **回答风格可调**：`config.json` 的 `systemPrompt` 控制「先给结论、分点、简短、最小代码」，直接编辑即可改。
- **失败讲人话**：所有免费源都用不了时，会逐个列出原因而不是甩一个 HTTP 状态码 —— 额度用完会读 `Retry-After` / `X-RateLimit-Reset` 换算成「约 2.5 小时后恢复」，另有认证失败、余额不足、上游故障等分类；拿不到恢复时间就明说「未告知恢复时间」，不编造。最后附上接个人 key 的一行命令。

### 长记忆（省 token 的关键）

每轮对话按天存进 `<目录>/memory/YYYY-MM-DD.md`，并在 `index.json` 里建关键词索引。下次提问时**只检索并注入最相关的 3 条历史片段**，而不是把全部历史都塞进上下文——这是省 token 的核心。关键词用规则提取（滑窗 n-gram），零成本、不额外调用 AI。

相关配置（`config.json`）：`memoryEnabled`（默认 true）、`memoryTopN`（默认 3）。

## 五、自动检索最新免费 AI

- 内置了 5 个**已验证**的免费源（智谱/Groq/DeepSeek/Logfare/Gemini）。
- `omni free-list` 会**实时从 awesome-free-llm-apis 检索最新免费 AI 清单**（含注册链接），新出现的免费 AI 能第一时间看到并提示你去注册拿 key。
- MCP 工具 `omni_free_list` 同样提供检索能力。

## 六、接入编辑器

`omni editor` 打印三行连接信息，填进任何 OpenAI 兼容客户端：

```
base_url = http://localhost:20128/v1
api_key  = <自动生成的 key>
model    = auto
```

- **VS Code**：Cline 或 Continue 插件，选 OpenAI Compatible。
- **PyCharm / IDEA**：Continue 插件。
- **aider / opencode / cline**：设 `OPENAI_API_BASE`、`OPENAI_API_KEY`。
- **MCP（编辑器里的 AI 自助管理）**：`omni mcp` 打印 Cursor / Claude Desktop / Cline 的 MCP 配置。

## 七、文件位置

- 配置：`<你选的目录>/config.json`（默认 `~/.omniroute/`）
- 长记忆：`<目录>/memory/`（按天的 `.md` 分段文件 + `index.json` 关键词索引）
- 脚本：`omni.mjs` / `omni-watchdog.mjs` / `omni-mcp.mjs`（同目录；Windows 另有 `omni.cmd`）
- 卸载：`uninstall.bat` + `uninstall.ps1`（Win） / `uninstall.command`（Mac 双击） / `uninstall.sh`（Mac、Linux）
- 管理面板：<http://localhost:20128>（密码在 config.json 的 `adminPassword`）

## 八、一键卸载

卸载是**逐项可选**的，不是一刀切。运行后会先列出所有可删项、各自的实际体量、以及是否可恢复，你挑编号（空格分隔，`a` 表示全选，直接回车取消）：

```
  1  停止正在运行的服务                当前：运行中        可逆，随时能再启动
  2  全部对话记忆 memory/              12 天 / 340 条 / 2.1M   ⚠ 不可恢复
  3  配置 config.json（API key + 管理密码）                    ⚠ 不可恢复
  4  整个安装目录（含 2、3 和数据库）  ~/.omniroute  5.9M      ⚠ 不可恢复
  5  全局 npm 包 omniroute             2.3G                    可重新安装
  6  shell 里的 omni 命令（alias）                             可逆
  7  Docker 容器 omniroute                                     可逆
```

**不会删除 Node.js、Homebrew、Docker 本身** —— 它们大概率被你其它项目用着。

| 系统 | 怎么卸载 |
|---|---|
| Windows | 双击 `uninstall.bat` |
| macOS | 双击 `uninstall.command`（或终端输入 `bash ` 后把 `uninstall.sh` 拖进去） |
| Linux / 国产 Linux | 终端输入 `bash ` 后把 `uninstall.sh` 拖进去 |

删除前有四道保险：

1. **逐项选择**，默认什么都不删；直接回车即取消。
2. 选完后**按文件类型摊开**告诉你具体要删什么，例如：

   ```
   按文件类型列出将被删除的内容：
     · 对话记录  *.md × 12       你和 AI 的全部问答原文
     · 记忆索引  index.json      关键词索引，删了记忆检索就没了
     · 配置文件  config.json     含 API key 与管理面板密码
     · 数据库    storage.sqlite  omniroute 的全部数据（提供者、用量、密钥）
   ```

3. 再要求输入 `yes` 才真正执行——输入其它任何内容都会取消，且不碰任何文件。
4. 涉及不可恢复的内容时，默认提示先把 `config.json` 和整个 `memory/` **备份到桌面**；改 `.bashrc` / `.zshrc` 前也会先存一份 `.omni-bak`。

> Docker 镜像（数百 MB）会单独再问一次，默认**保留**。

## 九、常见问题

- **cmd 里跑 powershell 报「不是内部或外部命令」？** Windows 必须用 PowerShell，不是 cmd。请双击 `install.bat`（最简单），或在 `omni-free-llm` 文件夹里 Shift+右键 → 在此处打开 PowerShell。
- **安装完 `omni` 命令找不到？**
  - Windows：安装器会生成 `omni.cmd` 并把安装目录写进**用户级 PATH**，需要**重开一个 cmd 窗口**才生效。仍然不行就用全路径：`node "%USERPROFILE%\.omniroute\omni.mjs" chat`。
  - macOS / Linux：重开终端，或执行 `source ~/.bashrc`。
- **装好了但不知道怎么开始对话？** 运行 `omni chat`（不带参数），出现 `❯` 提示符就是会话模式，输入 `:q` 退出。
- **GitHub push 失败 / connector 报 403？** WorkBuddy 的 GitHub 连接器（OAuth App）没有仓库读写权限，请用一个 Personal Access Token（Fine-grained, Contents: Read and write）直接调 GitHub API。

## 十、免责声明

oMNIROUTE 为 MIT 协议开源项目；免费额度由各上游 provider 提供，可能随时调整或取消。聚合调用多个免费 tier 可能违反个别 provider 条款，请自行评估后再用于生产/商用。**请务必自行妥善保存你的 API key，本工具不存储、不上传。**
