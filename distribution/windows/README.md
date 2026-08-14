# Windows installer

English | [中文](README.zh.md)

`scripts/build-windows-installer.ps1` produces two user-scope Windows x64 setup executables for DeepSeek Desktop, a community package built from the published `@deepseek-ai/dsh` package.

Both setups bundle Node.js 22.19.0 after checking its SHA-256, open the local Harness UI inside a `DeepSeek Desktop` WebView window, and add one Start menu shortcut. They do not request administrator permissions or change the system `PATH`.

The offline setup includes the complete published Harness dependency closure. The online setup downloads that same fixed closure through `registry.npmmirror.com` while installing, then falls back to `registry.npmjs.org` if the mirror is unavailable. Application data stays in `%LOCALAPPDATA%\DeepSeek Harness Data`; the included uninstaller removes the program files and shortcut while preserving that data directory.

Each opening begins with a clear choice: **Free model (Groq Free Plan)** or **DeepSeek API**. The default Groq route preconfigures GPT-OSS 20B, GPT-OSS 120B, and Qwen3.6 27B in the embedded Harness model picker; it does not use a local model. The app opens directly to the selected route rather than an API-key screen. A Groq key is required only when the user configures that provider in the embedded Models settings; choosing DeepSeek API uses the existing embedded DeepSeek-key setup.

The installer shows a `Choose plugins...` button immediately after the non-official-distribution notice; the checked state is written to the current user's Web profile. The mandatory `deepseek-desktop-plugin-helper` is included in both setup modes and exposes a read-only local roster at `/__deepseek_desktop/plugin-helper`. The online setup downloads the selected network plugins during installation; the offline setup leaves those rows disabled. This source-only change does not rebuild a setup executable:

- `deepseek-desktop-free-fallback` switches to a second free model only when the primary route fails before its first output with a transient rate-limit, timeout, server, empty-response, or transport failure. It never changes routes after output has started.
- `deepseek-desktop-vision-preflight` checks explicit model modality metadata before sending an image and returns a readable error for models that declare no image support.
- `deepseek-desktop-web-diagnostics` exposes `http://127.0.0.1:<port>/__deepseek_desktop/diagnostics` so WebView loopback failures can be separated from model failures.
- `dsh-vision-sidecar` is captured into the payload as an npm package but stays disabled by default, preserving the text-only free route. Enable its profile row when image input is needed; the default hosted vision route is LLM7.io's anonymous endpoint.
- `dsh-session-export` downloads a pinned prebuilt GitHub package in the online setup and exports sessions as Markdown or JSON.
- `dsh-mic-input` downloads a pinned prebuilt GitHub package in the online setup and adds browser speech input with a `zh-CN` option.
- `dsh-client-auto-continue` and `dsh-web-attention-badge` download exact npm versions in the online setup; both remain selectable in the installer.

The reasoning-effort slider is an in-tree UI improvement rather than a separately optional plugin, so it ships with the desktop UI when that bundle is rebuilt.

The plugins contain no API key and are not official DeepSeek components. Network plugin sources are pinned in `scripts/build-windows-installer.ps1`; the installer uses `--ignore-scripts` so downloaded packages cannot run npm lifecycle scripts.

## Build

Run this from a PowerShell session in the repository root:

```powershell
.\scripts\build-windows-installer.ps1
```

The `Online` setup and `Offline` setup are written to `distribution/windows/dist/`. The builder creates a fresh directory under `distribution/windows/build/` and refuses to overwrite an existing release asset. The builder verifies the bundled Node.js archive internally but does not create checksum sidecar files for release upload.

## Verification

Before publishing, run both setup executables in a Windows user session. After installation, start **DeepSeek Desktop** from the Start menu and confirm that its embedded window loads the local UI.

The installer is an independent community distribution. It includes no API key and does not claim to be an official DeepSeek release.
