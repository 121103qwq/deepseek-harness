# `@deepseek-ai/dsh-manager`

[English](README.md) | 中文

Windows DSh Manager 是一个类似 PCL2 的本地管理器和启动器。它维护 DSh 安装目录与源码工作区列表，为每个实例提供独立的 DSh Home，并在单独的聊天 WebView 窗口中打开每个运行实例。

## 可管理的资源

- 实例：可以从 `%USERPROFILE%\Documents\DeepSeek` 或其他文件夹手动添加 DSh 安装目录和源码项目。
- 扩展：发现官方 `@deepseek-ai/dsh-*` npm 包、带有 GitHub `dsh-plugin` topic 的仓库，以及用户提供的 JSON 目录。插件安装交给 DSh 处理；Skill 仓库和本地 Skill 会复制到选中的实例。
- Skill：实例 Skill 保存在管理器自己的 `skills` 目录中；项目 `.dsh/skills` 和 `.agents/skills` 以只读方式显示，同时显示模型调用和用户调用元数据。
- 对话：实例可以加入同步组。同步组只共享会话文件；插件、Skill、设置、权限和运行时 Home 仍然隔离。
- 生命周期：每个实例都会记录识别、启动中、运行中、健康检查、停止、重启、端口/PID、最后启动时间和最近日志状态。首版同步组只允许一个实例运行。
- 模型、Agent 预设、工作流、MCP、工具、权限、日志、诊断、备份和更新入口都放在管理器导航中，后续可以继续扩展而不混用实例数据。

## 开发

在仓库根目录执行：

```powershell
pnpm --filter @deepseek-ai/dsh-manager run build
pnpm --filter @deepseek-ai/dsh-manager run server -- --port 3210
```

服务只监听回环地址。`DSH_MANAGER_DATA_ROOT` 和 `DSH_MANAGER_DOCUMENTS_ROOT` 可以覆盖本地注册表目录与默认 Documents 文件夹；`DSH_MANAGER_NODE` 用于指定启动 DSh 实例时使用的 Node 可执行文件。管理器登记信息不会写入 DSh 配置文件或源码项目；只有用户明确执行插件操作时，才会在该实例隔离的 `DSH_HOME` 下让 DSh 维护 profile 文件。

`distribution/windows/templates/DeepSeekManager.cs` 中的 Windows 宿主会把管理器服务、前端资源和 Node 运行时嵌入单一输出文件 `DSH luncher.exe`，启动时释放到用户本地数据目录，提供原生文件夹选择器，并在独立的 WebView2 窗口中打开启动后的聊天地址。

这个启动器的公开仓库是 [DSH-Launcher](https://github.com/121103qwq/DSH-Launcher)。
