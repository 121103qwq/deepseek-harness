# Agent Note: Windows DSh manager and launcher

Status: implemented

[English](2026-08-14-dsh-manager-launcher.md) | 中文

## Problem

Windows 用户需要在一个地方切换 DSh 安装实例和源码工作区，同时避免实验性扩展与运行时设置在实例之间泄漏。管理器还必须区分可共享的对话与必须隔离的运行时资源。

## Decision

仓库新增私有 workspace `@deepseek-ai/dsh-manager` 和 Windows WebView2 宿主。用户看到的 `DSH luncher.exe` 会把管理器服务、前端资源和 Node 运行时嵌入其中，启动时释放到 `%LOCALAPPDATA%\DeepSeek Harness Manager`，在那里保存注册表，为每个登记的实例提供管理器独立维护的 DSh Home，分配回环端口，启动 DSh Web profile，并在独立聊天窗口中打开返回的地址。

界面使用类似 PCL2 的文件夹与卡片布局，覆盖启动、实例管理、扩展发现、Skill、对话、模型、Agent 预设和诊断。官方 npm 包使用 `@deepseek-ai/dsh-*` 命名空间。社区插件通过 GitHub `dsh-plugin` topic 发现，用户目录只接受明确提供的 HTTP(S) 地址。未验证的社区条目会在安装前显示警告。

实例生命周期会记录识别、启动中、运行中、HTTP 健康、停止、重启、日志、端口、PID、最后启动时间、收藏状态、图标和描述。同步组在已有成员运行时拒绝第二个实例启动。source 和 installed 在界面中保持明显区分；首版商店按已验证优先、名称排序。

实例默认隔离。管理器登记信息只保存在管理器数据目录中，不会进入 DSh 配置文件或源码项目。同步组只改变 session-persistence 的根目录，不共享实例 Home、插件、Skill、设置、权限、日志或运行时进程。本地 Skill 会复制到选中的实例，并可在管理器界面删除；项目 Skill 保持只读。明确执行插件操作时，管理器会使用该实例隔离的 `DSH_HOME` 调用 DSh。

## Alternatives considered

**复用 DeepSeek Desktop 作为管理器窗口。** 不采用，因为实例选择与聊天会话需要独立生命周期；管理器应在选中实例停止或更换时保持打开。

**共享一个全局 DSh Home。** 不采用，因为一个实例中的插件、Skill、模型、Agent 和权限变化会影响其他实例。

**把所有 GitHub 仓库都视为可安装。** 不采用，因为市场发现需要明确的 `dsh-plugin` 标志，未验证的社区代码也必须保持明显的未验证状态。

**同步全部实例数据。** 不采用，因为只有对话适合在实例之间共享；同步可执行扩展或设置会破坏隔离。

## Consequences

管理器可以在不修改全局 PATH 的情况下启动源码实例和安装实例。Windows 分发物只暴露一个管理器可执行文件，首次启动时会在用户数据目录下释放私有运行时文件。源码启动通过项目 TypeScript 入口并使用该 Node 运行时，因此可用的源码项目仍需拥有自己的依赖和已构建的前端产物。管理器回环服务与 DSh 聊天进程相互独立，因此可以分别诊断管理器和聊天进程的日志与失败。

模型、Agent、工作流、MCP、工具、权限、备份和更新导航建立了管理器的资源词汇；后续可以增加针对运行时的编辑器，而不改变注册表和隔离规则。安装程序会把管理器与 DeepSeek Desktop 一起安装，并添加开始菜单快捷方式；本次改动不会创建 GitHub 仓库或 Release。
