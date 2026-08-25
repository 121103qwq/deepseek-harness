# Agent Note: Desktop update synchronization

Status: implemented

English | [English](2026-08-14-desktop-update-sync.md)

## Problem

Windows 社区安装包需要一个统一入口，同时发现官方 Harness 项目和本社区发行版的更新。后台检查不能变成无人确认的可执行文件下载或安装，因为本安装包明确独立于 DeepSeek 官方。

## Decision

安装程序内置并默认启用 `deepseek-desktop-update-sync`。插件在启动后及每六小时检查 `deepseek-ai/deepseek-harness` 和 `121103qwq/deepseek-harness` 的最新 GitHub Release 元数据，并在 `/__deepseek_desktop/update-sync` 提供只读状态。安装程序允许用户关闭后台检查，或主动开启后台下载暂存。主动开启暂存后，只接受 DeepSeek Desktop 离线安装程序，大小限制为 330 MiB；必须取得并校验 GitHub 提供的 SHA-256 摘要，然后才会写入当前用户的更新目录；插件不会启动或安装暂存的可执行文件。

插件使用 Release 元数据，不会修改源代码检出，也不会静默改变当前 profile。如果社区仓库尚未发布 Release，会报告 `not_published`，因此可以在第一个桌面资产发布前继续检查该仓库。

## Alternatives considered

**静默自动安装** —— 否决，因为这会在用户未明确操作时执行安装程序，可能触发提权或重启，并削弱独立社区发行的归属边界。

**只检查一个仓库** —— 否决，因为官方 Harness 更新和社区桌面安装包更新由不同的发布者负责，二者可能独立推进。

**只做 Web UI 设置卡片** —— 暂缓，因为 Windows 载荷已有首次安装选项，可以在不改共享 Web UI 设置包的情况下持久化两个安全开关。本地状态端点为以后增加应用内设置界面保留入口。

## Consequences

默认安装会在后台发起少量 GitHub 元数据请求，但不会下载安装程序。开启后台下载的用户会得到一个暂存文件和状态记录，仍需在之后确认是否运行。端点只保留内存状态，不暴露 profile 路径、凭据或完整 Release 响应。
