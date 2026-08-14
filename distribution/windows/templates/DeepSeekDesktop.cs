using System;
using System.Diagnostics;
using System.IO;
using System.Net.Sockets;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

internal static class DeepSeekDesktop
{
    [STAThread]
    private static void Main()
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new DesktopForm());
    }
}

internal sealed class DesktopForm : Form
{
    private const int Port = 3080;
    private readonly WebView2 view = new WebView2 { Dock = DockStyle.Fill };
    private Process server;
    private System.Drawing.Icon applicationIcon;
    private string serverLogPath;
    private bool navigationDiagnosticShown;

    private enum ModelMode
    {
        Free,
        DeepSeekApi,
    }

    internal DesktopForm()
    {
        Text = "DeepSeek Desktop";
        Width = 1440;
        Height = 920;
        MinimumSize = new System.Drawing.Size(960, 640);
        LoadApplicationIcon();
        Controls.Add(view);
        Shown += async (_, __) =>
        {
            try
            {
                var mode = ChooseModelMode();
                if (!mode.HasValue)
                {
                    Close();
                    return;
                }
                ApplyModelMode(mode.Value);
                StartServer();
                WaitForServer();
                await view.EnsureCoreWebView2Async();
                view.CoreWebView2.Settings.AreDevToolsEnabled = false;
                view.CoreWebView2.Settings.AreDefaultContextMenusEnabled = false;
                view.NavigationCompleted += OnNavigationCompleted;
                view.CoreWebView2.ProcessFailed += OnWebViewProcessFailed;
                view.CoreWebView2.Navigate("http://127.0.0.1:3080");
            }
            catch (Exception error)
            {
                ShowStartupDiagnostics(error);
                Close();
            }
        };
        FormClosed += (_, __) =>
        {
            try
            {
                if (server != null && !server.HasExited) server.Kill();
            }
            catch
            {
                // The server may have exited between the check and Kill().
            }
        };
    }

    private void LoadApplicationIcon()
    {
        string logo = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "DeepSeek-Black-Logo.png");
        if (!File.Exists(logo)) return;
        using (var bitmap = new System.Drawing.Bitmap(logo))
        {
            applicationIcon = System.Drawing.Icon.FromHandle(bitmap.GetHicon());
            Icon = applicationIcon;
        }
    }

    private ModelMode? ChooseModelMode()
    {
        using (var dialog = new Form())
        {
            dialog.Text = "DeepSeek Desktop";
            dialog.FormBorderStyle = FormBorderStyle.FixedDialog;
            dialog.StartPosition = FormStartPosition.CenterParent;
            dialog.ClientSize = new System.Drawing.Size(560, 275);
            dialog.MinimizeBox = false;
            dialog.MaximizeBox = false;
            dialog.ShowInTaskbar = false;

            var title = new Label
            {
                Text = "选择本次使用的模型",
                AutoSize = true,
                Font = new System.Drawing.Font(System.Drawing.SystemFonts.MessageBoxFont.FontFamily, 15, System.Drawing.FontStyle.Bold),
                Location = new System.Drawing.Point(28, 26),
            };
            var detail = new Label
            {
                Text = "Groq 提供免费额度；选中后在内置 Harness 的模型设置中填入 Groq key。DeepSeek API 也在内置界面中配置密钥。",
                AutoSize = true,
                MaximumSize = new System.Drawing.Size(500, 0),
                Location = new System.Drawing.Point(30, 68),
            };
            var free = new Button
            {
                Text = "免费模型（Groq Free Plan）",
                DialogResult = DialogResult.Yes,
                Size = new System.Drawing.Size(225, 88),
                Location = new System.Drawing.Point(30, 132),
            };
            var api = new Button
            {
                Text = "DeepSeek API",
                DialogResult = DialogResult.No,
                Size = new System.Drawing.Size(225, 88),
                Location = new System.Drawing.Point(305, 132),
            };
            dialog.Controls.AddRange(new Control[] { title, detail, free, api });
            dialog.AcceptButton = free;
            var result = dialog.ShowDialog(this);
            if (result == DialogResult.Yes) return ModelMode.Free;
            if (result == DialogResult.No) return ModelMode.DeepSeekApi;
            return null;
        }
    }

    private static void ApplyModelMode(ModelMode mode)
    {
        string home = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DeepSeek Harness Data");
        string patch = Path.Combine(home, "profiles", "web", "cordis.patch.yml");
        if (!File.Exists(patch)) throw new InvalidOperationException("DeepSeek Desktop setup is incomplete. Reinstall the application.");
        string disabled = "- id: llm-deepseek\r\n  disabled: true";
        string enabled = "- id: llm-deepseek";
        string freeDefault = "provider: groq\r\n    model: openai/gpt-oss-20b";
        string deepSeekDefault = "provider: deepseek-official\r\n    model: deepseek-v4-flash";
        string text = File.ReadAllText(patch);
        if (mode == ModelMode.Free)
        {
            text = text.Replace(deepSeekDefault, freeDefault);
            text = text.Replace(enabled + "\r\n  disabled: true", disabled).Replace(enabled + "\n  disabled: true", disabled);
            if (!text.Contains(disabled)) text = text.Replace(enabled, disabled);
        }
        else
        {
            text = text.Replace(freeDefault, deepSeekDefault);
            text = text.Replace(disabled, enabled).Replace("- id: llm-deepseek\n  disabled: true", enabled);
        }
        File.WriteAllText(patch, text);
    }

    private void StartServer()
    {
        string root = AppDomain.CurrentDomain.BaseDirectory;
        string home = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DeepSeek Harness Data");
        Directory.CreateDirectory(home);
        string node = Path.Combine(root, "runtime", "node.exe");
        string bin = Path.Combine(root, "app", "node_modules", "@deepseek-ai", "dsh", "lib", "bin.js");
        if (!File.Exists(node) || !File.Exists(bin)) throw new InvalidOperationException("DeepSeek Desktop is incomplete. Reinstall the application.");
        string logDirectory = Path.Combine(home, "logs");
        Directory.CreateDirectory(logDirectory);
        serverLogPath = Path.Combine(logDirectory, "desktop-harness.log");
        File.AppendAllText(serverLogPath, "\r\n--- DeepSeek Desktop start " + DateTime.Now.ToString("O") + " ---\r\n");
        var start = new ProcessStartInfo(node, "\"" + bin + "\" web --port " + Port)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = root,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        start.EnvironmentVariables["DSH_HOME"] = home;
        start.EnvironmentVariables["DSH_WEB_DESKTOP"] = "1";
        server = Process.Start(start);
        if (server == null) throw new InvalidOperationException("DeepSeek Desktop could not start the local Harness service.");
        server.OutputDataReceived += (_, args) => AppendServerLog(args.Data);
        server.ErrorDataReceived += (_, args) => AppendServerLog(args.Data);
        server.BeginOutputReadLine();
        server.BeginErrorReadLine();
    }

    private void WaitForServer()
    {
        var deadline = DateTime.UtcNow.AddSeconds(30);
        while (DateTime.UtcNow < deadline)
        {
            if (server != null && server.HasExited)
            {
                throw new InvalidOperationException("DeepSeek Desktop 的本地 Harness 服务已退出（代码 " + server.ExitCode + "）。");
            }
            try
            {
                using (var client = new TcpClient())
                {
                    client.Connect("127.0.0.1", Port);
                    return;
                }
            }
            catch (SocketException)
            {
                Thread.Sleep(250);
            }
        }
        throw new TimeoutException("DeepSeek Desktop 本地服务在 30 秒内没有响应。");
    }

    private void AppendServerLog(string line)
    {
        if (String.IsNullOrEmpty(line) || String.IsNullOrEmpty(serverLogPath)) return;
        try
        {
            File.AppendAllText(serverLogPath, DateTime.Now.ToString("O") + " " + line + Environment.NewLine);
        }
        catch
        {
            // Diagnostics must never terminate the desktop host.
        }
    }

    private void ShowStartupDiagnostics(Exception error)
    {
        string log = String.IsNullOrEmpty(serverLogPath) ? "未创建（服务尚未启动）" : serverLogPath;
        string message = "DeepSeek Desktop 无法连接内置 Harness。\r\n\r\n"
            + "本地地址：http://127.0.0.1:" + Port + "\r\n"
            + "诊断地址：http://127.0.0.1:" + Port + "/__deepseek_desktop/diagnostics\r\n"
            + "服务日志：" + log + "\r\n\r\n"
            + "错误：" + error.Message;
        MessageBox.Show(message, "DeepSeek Desktop 本地连接诊断", MessageBoxButtons.OK, MessageBoxIcon.Error);
    }

    private void OnNavigationCompleted(object sender, CoreWebView2NavigationCompletedEventArgs args)
    {
        if (args.IsSuccess || navigationDiagnosticShown) return;
        navigationDiagnosticShown = true;
        string html = "<html><head><meta charset='utf-8'><style>"
            + "body{font-family:Segoe UI,Microsoft YaHei,sans-serif;background:#0f172a;color:#e2e8f0;padding:42px;}"
            + "h1{color:#93c5fd;}code{color:#bfdbfe;}li{margin:10px 0;}"
            + "</style></head><body><h1>DeepSeek Desktop 本地连接诊断</h1>"
            + "<p>内置 WebView 无法加载 Harness 页面。</p><ul>"
            + "<li>本地地址：<code>http://127.0.0.1:" + Port + "</code></li>"
            + "<li>诊断地址：<code>http://127.0.0.1:" + Port + "/__deepseek_desktop/diagnostics</code></li>"
            + "<li>服务日志：<code>" + EscapeHtml(serverLogPath) + "</code></li>"
            + "<li>WebView 状态：<code>" + EscapeHtml(args.WebErrorStatus.ToString()) + "</code></li>"
            + "</ul><p>请先确认服务日志，再重新启动 DeepSeek Desktop。</p></body></html>";
        view.NavigateToString(html);
    }

    private void OnWebViewProcessFailed(object sender, CoreWebView2ProcessFailedEventArgs args)
    {
        if (navigationDiagnosticShown) return;
        navigationDiagnosticShown = true;
        MessageBox.Show(
            "内置 WebView 进程异常退出：" + args.ProcessFailedKind + "\r\n\r\n服务日志：" + serverLogPath,
            "DeepSeek Desktop WebView 诊断",
            MessageBoxButtons.OK,
            MessageBoxIcon.Error);
    }

    private static string EscapeHtml(string value)
    {
        if (String.IsNullOrEmpty(value)) return "";
        return value.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace("\"", "&quot;");
    }
}
