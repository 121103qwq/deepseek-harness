# Windows installer

English | [中文](README.zh.md)

This directory owns the unofficial **DeepSeek Desktop** Windows x64 distribution. `scripts/build-windows-installer.ps1` produces one self-contained, current-user installer named `Deepseek-desktop-offline.exe`; no online or mirror-downloading setup is published.

The installer bundles Node.js 24.19.0, `@deepseek-ai/dsh` 0.1.1-rc.2, WebView2 bindings, the complete production dependency closure, and every listed desktop plugin. It installs under `%LOCALAPPDATA%\Programs\DeepSeek Desktop` by default, registers the application and uninstaller in HKCU, creates Start menu shortcuts, and optionally creates a desktop shortcut. It does not request administrator rights, change the system `PATH`, open PowerShell, or defer dependency work to first launch.

Installation displays an explicit community-distribution notice, a destination page, selectable components, and native installation progress. Before committing configuration, the hidden configurator acquires the same per-`DSH_HOME` lock used by DSH Launcher, applies provider and plugin changes as one rollback-capable update, starts the bundled Web profile, and checks the plugin-helper inventory. A failed check restores the previous profile and settings instead of leaving a partly configured installation.

DeepSeek Desktop hosts the local Harness UI in an embedded WebView rather than opening a browser. Its Node process uses a loopback-only port, inherits standard `HTTP_PROXY`, `HTTPS_PROXY`, and `NO_PROXY` environment settings, and is terminated with the desktop process. The first close asks whether future closes should minimize to the system tray or exit directly. Uninstall removes program files, shortcuts, App Paths, and uninstall registration while preserving `%LOCALAPPDATA%\DeepSeek Harness Data`.

## Models

The default route is **Kilo Auto Free**, an anonymous hosted model selected automatically without a login or API key. **LLM7** is installed as an anonymous fallback for transient failures before the first model output. The installer can instead select the built-in **DeepSeek API** route, which remains disabled until the user supplies their own key in Harness settings.

No credential is embedded in the installer. Kilo and LLM7 are remote services, not local models; their availability, limits, underlying models, and retention policies are controlled by their operators. The installer warns users not to send sensitive data through anonymous free routes.

## Plugins

All plugin files are present before the installer starts. Every component except the experimental vision sidecar is selected by default; clearing a component disables its profile row without downloading or deleting files.

- `deepseek-desktop-plugin-helper` reports the installed plugin ids and enabled state at the loopback-only `/__deepseek_desktop/plugin-helper` endpoint and is always enabled.
- `deepseek-desktop-update-sync` checks official Harness and community GitHub Releases every six hours by default. Background download staging is opt-in, accepts only the offline desktop asset up to 330 MiB with a GitHub digest, and never launches or installs it.
- `deepseek-desktop-free-fallback` changes from Kilo to LLM7 only when a transient failure occurs before the first output.
- `deepseek-desktop-vision-preflight` rejects unsupported image input with a readable explanation.
- `deepseek-desktop-web-diagnostics` exposes loopback-only runtime and plugin diagnostics.
- `dsh-session-export` exports sessions as Markdown or JSON.
- `dsh-mic-input` adds WebView speech input with Chinese selected by default.
- `dsh-client-auto-continue` resumes eligible interrupted requests and includes an RC2 keyed-slot compatibility patch in the assembled payload.
- `dsh-web-attention-badge` adds a window-level attention indicator.
- `@deepseek-ai/dsh-client-ui-model-selection` exposes supported reasoning-effort choices in the model picker.
- `dsh-vision-sidecar` provides an experimental hosted vision route and stays disabled by default.

Third-party packages are pinned in `scripts/build-windows-installer.ps1`. Assembly uses `--ignore-scripts`, so those packages cannot execute npm lifecycle scripts during the build or user installation.

## Build

Run from a Windows PowerShell session in the repository root after the repository packages have been built:

```powershell
.\scripts\build-windows-installer.ps1
```

The builder downloads only pinned build inputs, verifies the Node.js and WebView2 package SHA-256 values, assembles a hoisted production dependency tree, rebuilds the trusted `node-pty` native dependency, compiles the WinForms hosts, and writes `distribution/windows/dist/Deepseek-desktop-offline.exe`. It refuses to overwrite an existing release asset and does not create a checksum sidecar for publication.

## Release verification

Before publishing, install the generated executable into a clean current-user directory, confirm the configurator log reports a successful plugin-chain check, launch the embedded UI, inspect the Models and Plugins pages, and exercise the chosen provider. Then uninstall, confirm registration and program files are removed while `DSH_HOME` remains, and reinstall once more.

The current community executable is not code-signed. Windows Defender or SmartScreen may therefore show an unknown-publisher warning; do not bypass an antivirus detection, and publish the exact locally verified asset only through this repository's GitHub Release.
