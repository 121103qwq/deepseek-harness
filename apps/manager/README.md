# `@deepseek-ai/dsh-manager`

English | [中文](README.zh.md)

The Windows DSh Manager is a local PCL2-style manager and launcher. It keeps a list of DSh installation directories and source workspaces, gives every instance its own DSh Home, and opens each running instance in a separate chat WebView window.

## Managed resources

- Instances: installed DSh directories and source checkouts can be added manually from `%USERPROFILE%\Documents\DeepSeek` or any other folder.
- Extensions: the manager discovers official `@deepseek-ai/dsh-*` npm packages, GitHub repositories carrying the `dsh-plugin` topic, and user-supplied JSON catalogs. Plugin installation is delegated to DSh; Skill repositories and local Skills are copied into the selected instance.
- Skills: instance Skills live under the manager-owned `skills` directory. Project `.dsh/skills` and `.agents/skills` entries are shown read-only, including their model- and user-invocation metadata.
- Conversations: instances can join a sync group. Only session files are shared through that group; plugins, Skills, settings, permissions, and runtime homes remain isolated.
- Lifecycle: each instance exposes detection, starting, running, health, stopping, restarting, port/PID, last-launch, and recent-log state. A sync group permits only one running instance in the first release.
- Models, Agent presets, workflows, MCP, tools, permissions, logs, diagnostics, backup, and update entry points are represented in the manager navigation so the launcher can grow without mixing instance data.

## Development

From the repository root:

```powershell
pnpm --filter @deepseek-ai/dsh-manager run build
pnpm --filter @deepseek-ai/dsh-manager run server -- --port 3210
```

The server is loopback-only. `DSH_MANAGER_DATA_ROOT` and `DSH_MANAGER_DOCUMENTS_ROOT` override its local registry and default Documents folder. `DSH_MANAGER_NODE` selects the Node executable used to launch DSh instances. Manager registration data never goes into a DSh configuration file or source checkout; DSh profile files are touched only by an explicit plugin operation, under that instance's isolated `DSH_HOME`.

The Windows host in `distribution/windows/templates/DeepSeekManager.cs` embeds the Manager server, UI assets, and Node runtime into the single `DSH luncher.exe` output, extracts them into the user's local data directory at startup, supplies a native folder picker, and opens launched chat URLs in independent WebView2 windows.

The public repository for this launcher is [DSH-Launcher](https://github.com/121103qwq/DSH-Launcher).
