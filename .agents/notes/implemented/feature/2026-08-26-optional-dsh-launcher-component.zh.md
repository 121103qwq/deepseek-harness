# Agent Note: 可选的 DSH Launcher 安装组件

Status: implemented

[English](2026-08-26-optional-dsh-launcher-component.md) | 中文

## Problem

DeepSeek Desktop 用户需要直接安装独立开发的 DSH Launcher，而不必运行另一个安装程序，也不应在第一次启动时下载依赖。把两个应用合并到一个进程会耦合其数据与发布周期；把可执行文件直接复制到桌面则不符合正常安装布局，也无法可靠卸载。

## Decision

Windows 离线构建器要求显式传入一个已单独构建、带版本信息的 DSH Launcher Windows x64 单文件可执行程序。构建器会校验 PE 架构、文件版本和大小，再把该文件复制到独立的 `launcher` 载荷目录，并在 `desktop-install-manifest.json` 中记录版本、字节数和摘要。

NSIS 将 Launcher 显示为默认选中的组件，用户可以在组件页取消勾选。选中后，安装程序把 `DSH Launcher.exe` 放到 DeepSeek Desktop 程序目录下，并创建指向该副本的开始菜单和桌面快捷方式。Launcher 作为独立应用运行，保持自己的数据、应用身份、更新行为和 `DSH_HOME` 所有权规则。卸载程序会移除随附可执行文件和快捷方式，但不会删除 Launcher 或 Harness 的用户数据。

该可选组件扩展了 [Windows 离线 DeepSeek Desktop 安装程序](2026-08-26-windows-offline-desktop-installer.md)。它是独立开发的 DSH Launcher 应用，不是 [Windows DSh manager and launcher](2026-08-14-dsh-manager-launcher.md) 所述由 Harness 仓库维护的管理器宿主。

## Alternatives considered

**安装或首次启动时下载 Launcher。** 不采用，因为离线安装程序承诺一次确定的安装流程，并且必须在没有额外网络请求时可用。

**把可执行文件本身复制到桌面。** 不采用，因为桌面用于放置快捷方式，不是应用程序目录；程序目录中的副本才能为升级和卸载提供明确归属。

**把 Launcher 合并进 DeepSeek Desktop 进程。** 不采用，因为两个应用有独立的数据和发布周期，而且 Desktop 宿主未运行时，Launcher 仍需可用。

**把 Launcher 二进制提交到本仓库。** 不采用，因为生成的二进制不应进入源码历史。发布组装会显式接收经过验证的可执行程序，并只把它嵌入生成的安装资产。

## Consequences

即使用户取消该组件，离线资产仍会携带压缩后的 Launcher 字节，因此每个 Desktop 版本都必须保持在既有 330 MiB 限制内，并验证勾选与取消勾选两条安装路径。Desktop 发布还需要显式提供 Launcher 构建输入；安装程序不会用未经校验的下载代替。Launcher 保持独立开发，并可继续发布自己的 Release 资产。
