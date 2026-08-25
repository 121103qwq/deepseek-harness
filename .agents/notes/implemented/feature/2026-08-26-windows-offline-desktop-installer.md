# Agent Note: Windows offline DeepSeek Desktop installer

Status: implemented

English | [中文](2026-08-26-windows-offline-desktop-installer.zh.md)

## Problem

Windows users need one complete installer that registers as a normal per-user application, finishes runtime and plugin setup before first launch, and opens Harness in an embedded window. The package must remain an explicitly unofficial community distribution, avoid a mandatory API-key screen, and remain compatible with a separately distributed DSH Launcher without allowing both processes to modify the same Harness Home concurrently.

## Decision

The repository builds one x64 offline NSIS installer named `Deepseek-desktop-offline.exe`. Its embedded payload contains Node.js 24, the published Harness package, WebView2 bindings, the desktop host, configuration helper, and every supported plugin. The native installer shows the unofficial-distribution notice, model route, update, shortcut, and plugin choices; writes configuration transactionally; runs a local plugin-chain startup probe; and registers uninstall and App Paths metadata. First launch performs no dependency or plugin installation.

The desktop host uses an embedded WebView2 window and a loopback Harness server. It acquires the normalized `DSH_HOME` lock before any recovery or startup work, owns the Node process through a Windows job object, and preserves residual state when shutdown fails. The separately distributed DSH Launcher uses the same lock identity and discovers the installed application through its file layout and Windows registration.

The default route is Kilo Auto Free with no account or API key, with anonymous LLM7 as a configured fallback. The official DeepSeek API route remains an installation-time alternative and requires the user to add a key later. Node.js 24 enables environment-proxy support for anonymous remote models. The installer clearly states that free providers receive submitted prompts and may impose or change limits.

The installed plugins include provider fallback, diagnostics, update synchronization, configuration helper, session export, microphone input, automatic continuation, attention badge, reasoning-effort selection, and an optional vision sidecar. Background update checks cover the official Harness repository and this community distribution. A downloaded installer is staged only after the release asset, size limit, GitHub digest, and Windows executable format pass validation; it is never run automatically.

## Alternatives considered

**A small network installer with mirror fallback.** Rejected for this release because dependency download latency and mirror failures made installation timing unpredictable. It may return only with content-addressed downloads, native per-file progress, validated fallback, and transactional rollback.

**Install dependencies on first launch.** Rejected because it turns the first application window into an opaque second installer and leaves partially initialized user state when a download or plugin fails.

**Open the Harness URL in the system browser or ship Electron.** Rejected because a browser does not provide a desktop application lifecycle, while Electron duplicates a large browser runtime. WebView2 supplies the embedded window with a smaller package.

**Reuse official DeepSeek identity or bundle DSH Launcher.** Rejected because the package is a community distribution and the launcher has an independent release lifecycle. The shared runtime layout and startup lock provide compatibility without combining the products.

## Consequences

The installer is larger than a downloader but stays below the 330 MiB release limit and gives users one deterministic installation step. Plugin or runtime changes require rebuilding the offline asset. Windows Defender or SmartScreen may warn because the executable is not code-signed; the installer does not bypass those controls. A compatible WebView2 Runtime must be present on Windows, while all Harness, Node.js, plugin, and binding files are carried in the installer.
