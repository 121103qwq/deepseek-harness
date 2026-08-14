# DeepSeek Desktop：macOS 版

[English](README.md) | 中文

这是基于已发布 `@deepseek-ai/dsh` 包的实验性社区 macOS 分发版，不代表 DeepSeek 官方应用。

原生窗口使用 AppKit 与 `WKWebView`；Harness 服务只监听 `127.0.0.1`，不会额外打开浏览器。应用会内置 Node.js、已发布的 Harness 依赖闭包、桌面诊断插件，以及捕获的 `dsh-vision-sidecar` 源码；默认 profile 会保持视觉 sidecar 关闭。

首次启动只显示一次模型路线选择：Groq Free Plan 或 DeepSeek API。选择会写入 `~/Library/Application Support/DeepSeek Harness Data/profiles/web/cordis.patch.yml`，以后启动复用该选择。应用不内置任何 API key。

## 构建

请在安装了 Xcode Command Line Tools 的 macOS 上运行：

```sh
./scripts/build-macos-app.sh
```

脚本支持 Apple Silicon（Apple Silicon 默认使用 `arm64`）和 Intel（设置 `DEEPSEEK_MACOS_ARCH=x64`）。它会下载并校验固定版本的 Node.js，使用 `--install-links` 安装 npm 依赖，编译原生窗口，生成临时签名的 `.app`，并制作 `.dmg`。正式公证前设置 `DEEPSEEK_MACOS_CODESIGN_IDENTITY` 为 Developer ID 签名身份。

当前 Windows 工作区无法编译或启动 macOS 应用；发布 Release 前仍需在 macOS runner 上验证 `.app` 启动、首次模型选择、内置 WebView、关闭行为以及 Gatekeeper／公证策略。
