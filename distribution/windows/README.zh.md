# Windows 安装包

[English](README.md) | 中文

`scripts/build-windows-installer.ps1` 为 DeepSeek Desktop 生成两个仅限当前用户的 Windows x64 安装程序；它是基于已发布 `@deepseek-ai/dsh` 包的社区打包版。

两个安装程序都会在校验 SHA-256 后内置 Node.js 22.19.0，在名为 `DeepSeek Desktop` 的 WebView 窗口中打开本地 Harness UI，并添加一个开始菜单快捷方式。它们不请求管理员权限，也不修改系统 `PATH`。

载荷还包含可选的 `DSH luncher.exe` 管理器。它隔离管理多个 DSh 安装目录和源码工作区，为每个实例提供独立的 DSh Home，并在独立 WebView 窗口中打开选中的聊天。该管理器是社区启动器，不是 DeepSeek 官方应用。

完整离线版内置已发布 Harness 的完整依赖闭包。在线版会在安装时通过 `registry.npmmirror.com` 下载相同的固定依赖闭包；镜像不可用时自动回退到 `registry.npmjs.org`。应用数据保存在 `%LOCALAPPDATA%\DeepSeek Harness Data`；附带的卸载程序会移除程序文件和快捷方式，同时保留该数据目录。

每次打开都会明确提供两种选择：**免费模型（Groq Free Plan）** 或 **DeepSeek API**。默认 Groq 路由会在内置 Harness 模型选择器中预先配置 GPT-OSS 20B、GPT-OSS 120B 和 Qwen3.6 27B，不使用本地模型。应用会直接打开所选路由，而不是先显示 API key 页面；只有在内置“模型”设置中配置 Groq 时才需要其 key，选择 DeepSeek API 则使用原有的内置 DeepSeek key 配置流程。

安装程序会在“这是社区分发版本，不是 DeepSeek 官方安装程序”提示之后提供“选择插件…”按钮；勾选结果只写入当前用户的 Web profile。安装界面还提供两个更新选项：默认在后台检查更新；后台下载必须主动勾选，而且不会自动安装可执行文件。`deepseek-desktop-plugin-helper` 与 `deepseek-desktop-update-sync` 是两个安装模式都必须自带的插件；更新插件会检查官方上游仓库和本社区仓库，并通过 `/__deepseek_desktop/update-sync` 提供只读状态。在线版会在安装阶段下载已固定来源的网络插件；离线版会保留这些条目但默认关闭。本次只提交源码，不重新打包 setup：

- `deepseek-desktop-free-fallback`：免费路由在首个输出前遇到限流、超时、服务端或传输错误时，自动切换到备用免费模型；一旦已经产生输出，不会中途换模型。
- `deepseek-desktop-vision-preflight`：发送图片前读取模型能力；模型明确不支持图片时立即给出可读提示，不把图片静默发送给文本模型。
- `deepseek-desktop-web-diagnostics`：提供 `http://127.0.0.1:端口/__deepseek_desktop/diagnostics` 本地诊断端点，帮助区分 WebView 本地连接问题与模型请求问题。
- `deepseek-desktop-update-sync`：默认后台检查官方上游和本社区两个 GitHub Release；勾选后台下载后，会把匹配的安装程序暂存到当前用户目录，等待用户确认，不会自行启动或静默安装。
- `dsh-vision-sidecar`：随安装器预装的托管视觉插件，默认保持关闭，不改变免费文本模型；需要图片时可在 profile patch 中启用，默认使用 LLM7.io 的匿名视觉路由。
- `dsh-session-export`：在线版安装时下载固定提交的预构建 GitHub 包，支持 Markdown/JSON 会话导出。
- `dsh-mic-input`：在线版安装时下载固定提交的预构建 GitHub 包，增加浏览器语音输入并支持 `zh-CN`。
- `dsh-client-auto-continue` 与 `dsh-web-attention-badge`：在线版安装时下载固定版本的 npm 包，可在安装器中分别选择。

思考努力值滑杆是内置 UI 改进，不作为独立可选项；它随桌面界面一起安装。

这些插件不包含 API key，也不代表 DeepSeek 官方。网络插件的来源固定在 `scripts/build-windows-installer.ps1` 中；安装时使用 `--ignore-scripts`，不会执行下载包的 npm 生命周期脚本。

## 构建

在仓库根目录的 PowerShell 会话中运行：

```powershell
.\scripts\build-windows-installer.ps1
```

`Online` 安装程序和 `Offline` 安装程序会写入 `distribution/windows/dist/`。构建器会在 `distribution/windows/build/` 下新建目录，并拒绝覆盖已有的发布产物。构建器只在内部校验内置 Node.js 压缩包，不生成用于发布的校验文件。

## 验证

发布前，在 Windows 用户会话中运行两个安装程序。安装完成后，从开始菜单启动 **DeepSeek Desktop**，确认其内置窗口加载本地 UI。

该安装程序是独立的社区分发物，不含 API key，也不声称是 DeepSeek 官方发布。

同一个 payload 还会安装 **DSh Manager**，这是一个类似 PCL2 的 Windows 启动器，用于管理 DeepSeek Harness 生态。用户看到的管理器是单一文件 `DSH luncher.exe`；管理器服务、前端资源和 Node 运行时都嵌入其中，并在启动时自动释放。它可以登记安装实例或源码实例，在独立的聊天 WebView2 窗口中启动每个实例，管理插件和 Skill，发现官方 `@deepseek-ai/dsh-*` 包以及带有 GitHub `dsh-plugin` topic 的仓库，并将对话同步与每个实例的扩展和设置隔离开。管理器快捷方式会放在与 DeepSeek Desktop 相同的开始菜单文件夹中。它的公开仓库是 [DSH-Launcher](https://github.com/121103qwq/DSH-Launcher)。
