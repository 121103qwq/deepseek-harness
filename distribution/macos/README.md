# DeepSeek Desktop：macOS 版

English | [中文](README.zh.md)

This is an experimental community macOS distribution of the published `@deepseek-ai/dsh` package. It does not represent an official DeepSeek application.

The native host uses AppKit and `WKWebView`; the Harness service stays on `127.0.0.1` and is not opened in a separate browser. The app bundles Node.js, the published Harness dependency closure, the desktop diagnostics plugins, and the captured `dsh-vision-sidecar` source. The sidecar remains disabled by the default profile patch.

The first launch shows the model-route choice once: Groq Free Plan or DeepSeek API. The selected route is written to `~/Library/Application Support/DeepSeek Harness Data/profiles/web/cordis.patch.yml`; later launches reuse it. API keys are never embedded in the app.

## Build

Run on macOS with Xcode Command Line Tools:

```sh
./scripts/build-macos-app.sh
```

The script supports Apple Silicon (`arm64`, default on Apple Silicon) and Intel (`DEEPSEEK_MACOS_ARCH=x64`). It downloads and verifies the pinned Node.js runtime, installs npm dependencies with `--install-links`, compiles the native host, creates an ad-hoc signed `.app`, and produces a `.dmg`. Set `DEEPSEEK_MACOS_CODESIGN_IDENTITY` for a Developer ID signing identity before notarization.

This Windows checkout cannot compile or launch the macOS app. A macOS runner still needs to verify the `.app` launch, first-run choice, embedded WebView, quit behavior, and Gatekeeper/notarization policy before a Release is created.
