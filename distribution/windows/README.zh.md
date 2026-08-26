# Windows 安装包

[English](README.md) | 中文

本目录管理非官方 **DeepSeek Desktop** Windows x64 发行版。`scripts/build-windows-installer.ps1` 只生成一个当前用户范围的完整安装程序 `Deepseek-desktop-offline.exe`；不发布在线版或镜像下载版。

安装包内置 Node.js 24.19.0、`@deepseek-ai/dsh` 0.1.1-rc.2、WebView2 绑定、完整生产依赖闭包以及下文列出的全部桌面插件。默认安装到 `%LOCALAPPDATA%\Programs\DeepSeek Desktop`，在 HKCU 中注册应用和卸载程序，创建开始菜单快捷方式，并可选创建桌面快捷方式。它不请求管理员权限，不修改系统 `PATH`，不打开 PowerShell，也不会把依赖工作留到第一次启动。

组件页还提供可以独立运行的 **DSH Launcher** 管理器。选中后，安装程序会把经过校验的 Windows x64 单文件可执行程序安装到 Desktop 应用目录，并创建开始菜单和桌面快捷方式。取消勾选则不会安装 Launcher；卸载 DeepSeek Desktop 时只移除随附副本及其快捷方式。Launcher 保持独立的数据目录、发布周期和应用身份。

安装过程会显示明确的社区发行声明、目标目录页、可选组件和原生安装进度。隐藏配置器会在提交配置前获取与 DSH Launcher 相同的每 `DSH_HOME` 锁，将提供方和插件变更作为一次可回档更新执行，然后启动内置 Web profile 并检查插件 helper 清单。检查失败时会恢复原 profile 和设置，不留下部分配置的安装。

DeepSeek Desktop 使用内置 WebView 显示本地 Harness UI，不打开浏览器。Node 进程使用仅回环可访问的动态端口，继承标准 `HTTP_PROXY`、`HTTPS_PROXY` 和 `NO_PROXY` 环境设置，并会随桌面进程一起结束。第一次关闭会询问以后是最小化到系统托盘，还是直接退出。卸载会删除程序文件、快捷方式、App Paths 和卸载注册项，同时保留 `%LOCALAPPDATA%\DeepSeek Harness Data`。

## 模型

默认路线是 **Kilo Auto Free**：一个会自动选中、无需登录和 API key 的匿名托管模型。**LLM7** 会作为匿名备用路线，仅在首个模型输出前遇到短暂故障时切换。安装时也可以改选内置 **DeepSeek API** 路线；在用户于 Harness 设置中填写自己的 key 之前，该路线保持禁用。

安装包不内置任何凭据。Kilo 和 LLM7 都是远程服务，不是本地模型；它们的可用性、额度、底层模型和数据保留政策由服务方决定。安装界面会提醒用户不要通过匿名免费路线发送敏感数据。

## 插件

安装程序启动前，所有插件文件已经齐全。除实验性视觉 sidecar 之外，所有组件默认勾选；取消勾选只会禁用对应 profile 配置项，不会下载或删除文件。

- `deepseek-desktop-plugin-helper` 在仅回环可访问的 `/__deepseek_desktop/plugin-helper` 接口报告已安装插件 id 和启用状态，并且始终启用。
- `deepseek-desktop-update-sync` 默认每六小时检查官方 Harness 和社区 GitHub Release。后台下载暂存需要主动开启，只接受最大 330 MiB 且带 GitHub 摘要的离线桌面安装产物，永远不会启动或自动安装它。
- `deepseek-desktop-free-fallback` 仅在首个输出前发生短暂故障时，从 Kilo 切换到 LLM7。
- `deepseek-desktop-vision-preflight` 会为不支持的图片输入给出可读说明。
- `deepseek-desktop-web-diagnostics` 提供仅回环可访问的运行时和插件诊断。
- `dsh-session-export` 可以将会话导出为 Markdown 或 JSON。
- `dsh-mic-input` 增加 WebView 语音输入，并默认选中中文。
- `dsh-client-auto-continue` 会恢复符合条件的中断请求；组装 payload 内含 RC2 keyed slot 兼容补丁。
- `dsh-web-attention-badge` 增加窗口级任务提醒角标。
- `@deepseek-ai/dsh-client-ui-model-selection` 在模型选择器中提供已支持的推理强度选项。
- `dsh-vision-sidecar` 提供实验性托管视觉路线，默认保持禁用。

第三方包在 `scripts/build-windows-installer.ps1` 中固定来源。组装时使用 `--ignore-scripts`，因此这些包不能在构建或用户安装过程中执行 npm 生命周期脚本。

## 构建

在仓库包已经构建的前提下，从仓库根目录的 Windows PowerShell 会话运行：

```powershell
.\scripts\build-windows-installer.ps1 `
  -LauncherExecutable 'C:\path\to\DSH Launcher.exe'
```

传入的 Launcher 必须是带版本信息、以自包含单文件形式构建的 Windows x64 PE 可执行程序。构建器会校验其格式，在已安装清单中记录版本、大小和摘要，然后只下载固定的 Harness 构建输入，验证 Node.js 和 WebView2 包摘要，组装提升到顶层的生产依赖树，重新构建可信的 `node-pty` 原生依赖，编译 WinForms 宿主，并写入 `distribution/windows/dist/Deepseek-desktop-offline.exe`。它拒绝覆盖已存在的发布产物，也不会为发布生成摘要伴随文件。

## 发布验证

发布前，将生成的可执行文件安装到全新的当前用户目录，确认配置器日志报告插件链检查成功，启动内置 UI，检查“模型”和“插件”页，实际请求选定的提供方，并从桌面快捷方式启动随附 DSH Launcher。然后卸载，确认两个应用、快捷方式和注册项都已清除而用户数据仍保留；再取消 Launcher 组件重新安装，确认没有出现 Launcher 文件或快捷方式。

当前社区可执行文件未进行代码签名，因此 Windows Defender 或 SmartScreen 可能显示未知发布者警告。不要绕过杀毒软件的检出；只能通过本仓库的 GitHub Release 发布经本地验证的同一份产物。
