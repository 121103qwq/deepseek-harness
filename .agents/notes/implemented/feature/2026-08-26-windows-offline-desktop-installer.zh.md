# Agent Note: Windows 离线 DeepSeek Desktop 安装程序

Status: implemented

[English](2026-08-26-windows-offline-desktop-installer.md) | 中文

## Problem

Windows 用户需要一个完整安装程序：像普通的当前用户应用一样注册，在首次启动前完成运行时与插件配置，并在内置窗口中打开 Harness。该软件包必须明确标注为非官方社区发行版，不强制显示 API Key 填写页，并与单独分发的 DSH Launcher 兼容，同时禁止两个进程并发修改同一个 Harness Home。

## Decision

仓库构建一个名为 `Deepseek-desktop-offline.exe` 的 x64 离线 NSIS 安装程序。内置载荷包含 Node.js 24、已发布的 Harness 包、WebView2 绑定、桌面宿主、配置辅助程序、所有支持的插件，以及显式传入的 DSH Launcher 可执行程序。原生安装界面提供非官方发行提示、模型路线、更新、快捷方式、插件和可选 Launcher 选项；事务化写入配置；运行本地插件链启动探测；注册卸载信息与 App Paths。首次启动不会安装依赖或插件。[可选 Launcher 组件](2026-08-26-optional-dsh-launcher-component.md) 让两个应用保持独立运行。

桌面宿主使用内置 WebView2 窗口和回环 Harness 服务。在任何恢复或启动操作前，它会取得规范化 `DSH_HOME` 锁，通过 Windows 作业对象管理 Node 进程，并在关闭失败时保留残留状态。DSH Launcher 使用相同的锁标识，并通过文件布局与 Windows 注册信息发现已安装应用。

默认路线是不需要账户或 API Key 的 Kilo Auto Free，同时配置匿名 LLM7 作为备用。官方 DeepSeek API 路线仍可在安装时选择，用户需要之后添加 Key。Node.js 24 为匿名远程模型启用环境代理支持。安装程序明确说明免费服务商会接收提交的提示词，并且可能施加或调整限额。

已安装插件包括服务商回退、诊断、更新同步、配置辅助、会话导出、麦克风输入、自动继续、注意力徽标、思考努力值选择，以及可选的视觉 sidecar。后台更新会同时检查官方 Harness 仓库和本社区发行仓库。只有 Release 资产、大小限制、GitHub 摘要和 Windows 可执行文件格式全部通过校验后，安装程序才会被暂存；它永远不会自动运行。

## Alternatives considered

**带镜像回退的小型联网安装程序。** 本版本不采用，因为依赖下载延迟和镜像失败会让安装时长不可预测。只有具备内容寻址下载、原生逐文件进度、已验证回退和事务回滚时，才考虑恢复此方案。

**首次启动时安装依赖。** 不采用，因为这会把第一个应用窗口变成不透明的第二层安装程序，并在下载或插件失败时留下初始化不完整的用户状态。

**在系统浏览器中打开 Harness 地址或内置 Electron。** 不采用，因为浏览器无法提供桌面应用生命周期，而 Electron 会重复打包体积较大的浏览器运行时。WebView2 能以更小的软件包提供内置窗口。

**复用 DeepSeek 官方身份或把 DSH Launcher 设为 Desktop 必需核心。** 不采用，因为该软件包是社区发行版，Launcher 也有独立的发布周期。可选组件可以提供同一安装入口，同时避免合并两个产品或强制安装 Launcher。

## Consequences

安装程序比下载器更大，并携带可选 Launcher 字节，但仍保持在 330 MiB 发布限制内，为用户提供一次确定的安装流程。插件、运行时或随附 Launcher 发生变化时，需要重新构建离线资产。由于可执行文件没有代码签名，Windows Defender 或 SmartScreen 可能显示警告；安装程序不会绕过这些保护。Windows 需要具备兼容的 WebView2 Runtime，Harness、Node.js、插件和绑定文件则全部包含在安装程序中。
