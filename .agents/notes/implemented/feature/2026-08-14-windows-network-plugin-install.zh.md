# Agent Note: Windows 网络插件安装

Status: implemented

[English](2026-08-14-windows-network-plugin-install.md) | 中文

## Problem

Windows 桌面安装程序需要提供有用的社区插件，但不能让离线可执行文件随着每个可选包一起膨胀。可选下载必须可复现、不能执行包生命周期脚本，并且网络安装失败时仍要能诊断桌面程序的状态。

## Decision

离线 payload 始终包含 `deepseek-desktop-plugin-helper` 和现有桌面安全插件。在线 payload 保留同一组本地文件，然后在安装阶段注入四个可选网络依赖：`dsh-session-export` 和 `dsh-mic-input` 使用固定 GitHub 提交的归档，`dsh-client-auto-continue` 和 `dsh-web-attention-badge` 使用固定 npm 版本。安装程序优先使用 `registry.npmmirror.com`，失败后重试 `registry.npmjs.org`；所有 npm 安装都使用 `--ignore-scripts`，关闭 audit 和 funding 提示，并把插件选择写入 Web profile patch。

两个安装模式都必须包含 helper。它只提供只读的 `/__deepseek_desktop/plugin-helper` 接口，返回当前插件的 id、名称和启用状态，因此可选下载不完整时仍能观察状态，同时不会暴露凭据或修改配置。

## Alternatives considered

**把所有可选插件都放进离线 payload。** 不采用，因为离线可执行文件会变大，每次插件更新都需要重新构建两种安装模式。

**安装浮动的 GitHub 分支或执行包生命周期脚本。** 不采用，因为分支内容会漂移，生命周期脚本会在用户安装过程中增加不必要的供应链执行面。

**在安装程序中使用动态插件市场。** 不采用，因为安装内容必须可审查且固定；以后可以在已安装的应用内增加发现功能。

## Consequences

在线安装程序需要网络，并且由于两个 GitHub 包没有发布到 npm，可能直接下载 GitHub 归档。npm 镜像回退覆盖 Harness 依赖闭包和已发布到 npm 的可选包；GitHub 归档失败会使安装明确失败，而不会静默启用缺失插件。更新固定提交或版本需要有意修改 catalog 并重新构建安装程序。helper 增加了一个小型本地诊断面，但不会修复或启用插件。
