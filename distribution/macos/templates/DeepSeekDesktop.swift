import Cocoa
import Foundation
import WebKit

/// Native macOS host for the bundled DeepSeek Harness Web UI.
@main
final class DeepSeekDesktopApp: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate {
    private enum ModelMode {
        case free
        case deepSeekAPI
    }

    private enum ModelChoice {
        case existing
        case selected(ModelMode)
        case cancelled
    }

    private let port = 3080
    private var window: NSWindow!
    private var webView: WKWebView!
    private var server: Process?
    private var serverLogURL: URL?
    private var serverReady = false
    private var diagnosticsShown = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        makeWindow()
        DispatchQueue.main.async { [weak self] in
            self?.bootstrap()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        stopServer()
        return .terminateNow
    }

    private func makeWindow() {
        let frame = NSRect(x: 0, y: 0, width: 1440, height: 920)
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false,
        )
        window.title = "DeepSeek Desktop"
        window.minSize = NSSize(width: 960, height: 640)
        window.center()
        window.delegate = self

        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = self
        webView.autoresizingMask = [.width, .height]
        window.contentView = webView

        if let logoURL = Bundle.main.resourceURL?.appendingPathComponent("DeepSeek-Black-Logo.png"),
           let logo = NSImage(contentsOf: logoURL) {
            NSApp.applicationIconImage = logo
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        webView.loadHTMLString(loadingHTML, baseURL: nil)
    }

    private func bootstrap() {
        do {
            try ensureProfile()
            switch chooseModelModeIfNeeded() {
            case .cancelled:
                NSApp.terminate(nil)
                return
            case .existing:
                break
            case .selected(let mode):
                try applyModelMode(mode)
                try markModelChoiceConfigured()
            }
            try startServer()

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                do {
                    try self.waitForServer()
                    DispatchQueue.main.async {
                        self.serverReady = true
                        let url = URL(string: "http://127.0.0.1:\(self.port)")!
                        self.webView.load(URLRequest(url: url))
                    }
                } catch {
                    self.showStartupDiagnostics(error)
                }
            }
        } catch {
            showStartupDiagnostics(error)
        }
    }

    private var applicationSupportURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("DeepSeek Harness Data", isDirectory: true)
    }

    private var profilePatchURL: URL {
        applicationSupportURL.appendingPathComponent("profiles/web/cordis.patch.yml")
    }

    private func ensureProfile() throws {
        let fileManager = FileManager.default
        let profileDirectory = profilePatchURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: profilePatchURL.path) {
            guard let defaultPatch = Bundle.main.resourceURL?.appendingPathComponent("defaults/cordis.patch.yml") else {
                throw DesktopError.missingPayload("defaults/cordis.patch.yml")
            }
            try fileManager.copyItem(at: defaultPatch, to: profilePatchURL)
        }
        let settingsURL = applicationSupportURL.appendingPathComponent("settings.yaml")
        if !fileManager.fileExists(atPath: settingsURL.path) {
            try fileManager.createDirectory(at: applicationSupportURL, withIntermediateDirectories: true)
            try "ui-onboarding:\n  welcomeNoticeVersion: 2026-08-13.1\n".write(
                to: settingsURL,
                atomically: true,
                encoding: .utf8,
            )
        }
    }

    private func chooseModelModeIfNeeded() -> ModelChoice {
        let marker = applicationSupportURL.appendingPathComponent("macos-model-choice-v1")
        if FileManager.default.fileExists(atPath: marker.path) {
            return .existing
        }

        let alert = NSAlert()
        alert.messageText = "选择 DeepSeek Desktop 模型路线"
        alert.informativeText = "这是首次运行设置，只显示一次。免费模型使用 Groq Free Plan（需要在内置模型设置中填写 Groq key）；DeepSeek API 使用官方 API（需要填写 DeepSeek key）。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "免费模型（Groq Free Plan）")
        alert.addButton(withTitle: "DeepSeek API")
        alert.addButton(withTitle: "取消")

        let response = alert.runModal()
        let mode: ModelMode
        switch response {
        case .alertFirstButtonReturn:
            mode = .free
        case .alertSecondButtonReturn:
            mode = .deepSeekAPI
        default:
            return .cancelled
        }

        return .selected(mode)
    }

    private func markModelChoiceConfigured() throws {
        let marker = applicationSupportURL.appendingPathComponent("macos-model-choice-v1")
        try? FileManager.default.createDirectory(at: applicationSupportURL, withIntermediateDirectories: true)
        try Data("v1\n".utf8).write(to: marker, options: .atomic)
    }

    private func applyModelMode(_ mode: ModelMode) throws {
        var text = try String(contentsOf: profilePatchURL, encoding: .utf8)
        let freeDefault = "provider: groq\n    model: openai/gpt-oss-20b"
        let deepSeekDefault = "provider: deepseek-official\n    model: deepseek-v4-flash"
        let disabled = "- id: llm-deepseek\n  disabled: true"
        let enabled = "- id: llm-deepseek"

        switch mode {
        case .free:
            text = text.replacingOccurrences(of: deepSeekDefault, with: freeDefault)
            if !text.contains(disabled) {
                text = text.replacingOccurrences(of: enabled, with: disabled)
            }
        case .deepSeekAPI:
            text = text.replacingOccurrences(of: freeDefault, with: deepSeekDefault)
            text = text.replacingOccurrences(of: disabled, with: enabled)
        }

        try text.write(to: profilePatchURL, atomically: true, encoding: .utf8)
    }

    private func startServer() throws {
        guard let resourceURL = Bundle.main.resourceURL else {
            throw DesktopError.missingPayload("Contents/Resources")
        }
        let runtimeURL = resourceURL.appendingPathComponent("runtime", isDirectory: true)
        let nodeURL = runtimeURL.appendingPathComponent("bin/node")
        let binURL = resourceURL.appendingPathComponent("app/node_modules/@deepseek-ai/dsh/lib/bin.js")
        guard FileManager.default.isExecutableFile(atPath: nodeURL.path) else {
            throw DesktopError.missingPayload("runtime/bin/node")
        }
        guard FileManager.default.fileExists(atPath: binURL.path) else {
            throw DesktopError.missingPayload("app/node_modules/@deepseek-ai/dsh/lib/bin.js")
        }

        let logDirectory = applicationSupportURL.appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        serverLogURL = logDirectory.appendingPathComponent("desktop-harness.log")
        if let logURL = serverLogURL {
            try? "\n--- DeepSeek Desktop start ---\n".write(to: logURL, atomically: false, encoding: .utf8)
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let process = Process()
        process.executableURL = nodeURL
        process.arguments = [binURL.path, "--profile", "web", "--host", "127.0.0.1", "--port", String(port)]
        process.currentDirectoryURL = resourceURL
        var environment = ProcessInfo.processInfo.environment
        environment["DSH_HOME"] = applicationSupportURL.path
        environment["DSH_WEB_DESKTOP"] = "1"
        environment["PATH"] = runtimeURL.appendingPathComponent("bin").path + ":" + (environment["PATH"] ?? "")
        process.environment = environment
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.appendLog(handle.availableData)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.appendLog(handle.availableData)
        }
        process.terminationHandler = { [weak self] process in
            guard let self, !self.serverReady, process.terminationStatus != 0 else { return }
            self.showStartupDiagnostics(DesktopError.serverExited(process.terminationStatus))
        }
        try process.run()
        server = process
    }

    private func waitForServer() throws {
        let deadline = Date().addingTimeInterval(30)
        let url = URL(string: "http://127.0.0.1:\(port)/")!
        while Date() < deadline {
            if let server, !server.isRunning {
                throw DesktopError.serverExited(server.terminationStatus)
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 1
            let semaphore = DispatchSemaphore(value: 0)
            var response: URLResponse?
            URLSession.shared.dataTask(with: request) { _, result, _ in
                response = result
                semaphore.signal()
            }.resume()
            _ = semaphore.wait(timeout: .now() + 1.2)
            if (response as? HTTPURLResponse)?.statusCode == 200 {
                return
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        throw DesktopError.serverTimeout(port)
    }

    private func stopServer() {
        server?.terminate()
        server = nil
    }

    private func appendLog(_ data: Data) {
        guard !data.isEmpty, let logURL = serverLogURL else { return }
        guard let handle = try? FileHandle(forWritingTo: logURL) else {
            try? data.write(to: logURL, options: .atomic)
            return
        }
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    }

    private func showStartupDiagnostics(_ error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.diagnosticsShown else { return }
            self.diagnosticsShown = true
            let log = self.serverLogURL?.path ?? "未创建（服务尚未启动）"
            let html = """
            <html><meta charset="utf-8"><style>
            body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#0f172a;color:#e2e8f0;padding:42px}
            h1{color:#93c5fd}code{color:#bfdbfe}li{margin:10px 0}
            </style><body><h1>DeepSeek Desktop 本地连接诊断</h1>
            <p>内置 WKWebView 无法加载 Harness 页面。</p><ul>
            <li>本地地址：<code>http://127.0.0.1:\(self.port)</code></li>
            <li>诊断地址：<code>http://127.0.0.1:\(self.port)/__deepseek_desktop/diagnostics</code></li>
            <li>服务日志：<code>\(log)</code></li>
            <li>错误：<code>\(error.localizedDescription)</code></li>
            </ul><p>请先检查服务日志，再重新打开 DeepSeek Desktop。</p></body></html>
            """
            self.webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showStartupDiagnostics(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showStartupDiagnostics(error)
    }

    private var loadingHTML: String {
        """
        <html><meta charset="utf-8"><style>
        body{margin:0;display:grid;place-items:center;height:100vh;background:#0f172a;color:#e2e8f0;font-family:-apple-system,BlinkMacSystemFont,sans-serif}
        main{text-align:center}h1{font-size:28px;margin:0 0 12px;color:#f8fafc}p{color:#93c5fd}
        </style><body><main><h1>DeepSeek Desktop</h1><p>正在启动内置 Harness…</p></main></body></html>
        """
    }
}

private enum DesktopError: LocalizedError {
    case missingPayload(String)
    case serverExited(Int32)
    case serverTimeout(Int)

    var errorDescription: String? {
        switch self {
        case .missingPayload(let path):
            return "安装内容缺失：\(path)"
        case .serverExited(let status):
            return "本地 Harness 服务已退出（代码 \(status)）"
        case .serverTimeout(let port):
            return "本地 Harness 服务在 30 秒内没有响应（端口 \(port)）"
        }
    }
}
