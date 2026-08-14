using System;
using System.Diagnostics;
using System.IO;
using System.Net.Sockets;
using System.Reflection;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

internal static class DeepSeekManager
{
    [STAThread]
    private static void Main()
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new ManagerForm());
    }
}

internal sealed class ManagerForm : Form
{
    private const int Port = 3210;
    private readonly WebView2 view = new WebView2 { Dock = DockStyle.Fill };
    private Process manager;

    internal ManagerForm()
    {
        Text = "DSh Manager";
        Width = 1480;
        Height = 940;
        MinimumSize = new System.Drawing.Size(1040, 700);
        LoadIcon();
        Controls.Add(view);
        Shown += async (_, __) =>
        {
            try
            {
                StartManager();
                WaitForManager();
                await view.EnsureCoreWebView2Async();
                view.CoreWebView2.Settings.AreDevToolsEnabled = false;
                view.CoreWebView2.Settings.AreDefaultContextMenusEnabled = false;
                view.CoreWebView2.NewWindowRequested += OpenChatWindow;
                view.CoreWebView2.WebMessageReceived += HandleWebMessage;
                view.CoreWebView2.Navigate("http://127.0.0.1:" + Port);
            }
            catch (Exception error)
            {
                MessageBox.Show(this, "DSh Manager 无法启动。\r\n\r\n" + error.Message, "DSh Manager 启动诊断", MessageBoxButtons.OK, MessageBoxIcon.Error);
                Close();
            }
        };
        FormClosed += (_, __) => StopManagerTree();
    }

    private void LoadIcon()
    {
        string logo = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "DeepSeek-Black-Logo.png");
        if (!File.Exists(logo)) return;
        using (var bitmap = new System.Drawing.Bitmap(logo))
        {
            Icon = System.Drawing.Icon.FromHandle(bitmap.GetHicon());
        }
    }

    private void StartManager()
    {
        string data = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DeepSeek Harness Manager");
        string runtime = Path.Combine(data, "runtime");
        string app = Path.Combine(data, "app", "manager", "dist");
        string node = Path.Combine(runtime, "node.exe");
        string server = Path.Combine(app, "server.js");
        string documents = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "DeepSeek");
        Directory.CreateDirectory(data);
        Directory.CreateDirectory(documents);
        ExtractResource("DSH.Manager.Node", node);
        ExtractResource("DSH.Manager.Server", server);
        ExtractResource("DSH.Manager.Index", Path.Combine(app, "ui", "index.html"));
        ExtractResource("DSH.Manager.AppJs", Path.Combine(app, "ui", "assets", "app.js"));
        ExtractResource("DSH.Manager.AppCss", Path.Combine(app, "ui", "assets", "app.css"));
        var start = new ProcessStartInfo(node, "\"" + server + "\" --port " + Port)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = data,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        start.EnvironmentVariables["DSH_MANAGER_DATA_ROOT"] = data;
        start.EnvironmentVariables["DSH_MANAGER_DOCUMENTS_ROOT"] = documents;
        start.EnvironmentVariables["DSH_MANAGER_NODE"] = node;
        manager = Process.Start(start);
        if (manager == null) throw new InvalidOperationException("无法创建 DSh Manager 本地服务。");
    }

    private static void ExtractResource(string name, string path)
    {
        using (Stream source = Assembly.GetExecutingAssembly().GetManifestResourceStream(name))
        {
            if (source == null) throw new InvalidOperationException("DSh Manager 内置资源缺失：" + name);
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            using (var target = File.Create(path)) source.CopyTo(target);
        }
    }

    private void WaitForManager()
    {
        var deadline = DateTime.UtcNow.AddSeconds(20);
        while (DateTime.UtcNow < deadline)
        {
            if (manager != null && manager.HasExited) throw new InvalidOperationException("DSh Manager 服务已退出（代码 " + manager.ExitCode + "）。");
            try
            {
                using (var client = new TcpClient())
                {
                    client.Connect("127.0.0.1", Port);
                    return;
                }
            }
            catch (SocketException) { Thread.Sleep(200); }
        }
        throw new TimeoutException("DSh Manager 服务在 20 秒内没有响应。");
    }

    private void HandleWebMessage(object sender, CoreWebView2WebMessageReceivedEventArgs args)
    {
        string message = args.TryGetWebMessageAsString();
        if (message.IndexOf("\"type\":\"pick-folder\"", StringComparison.Ordinal) < 0) return;
        using (var dialog = new FolderBrowserDialog())
        {
            dialog.Description = "选择 DSh 安装目录或源码项目";
            dialog.ShowNewFolderButton = false;
            if (dialog.ShowDialog(this) == DialogResult.OK)
            {
                view.CoreWebView2.PostWebMessageAsJson("{\"type\":\"folder-selected\",\"path\":\"" + EscapeJson(dialog.SelectedPath) + "\"}");
            }
        }
    }

    private void OpenChatWindow(object sender, CoreWebView2NewWindowRequestedEventArgs args)
    {
        args.Handled = true;
        new ChatForm(args.Uri).Show(this);
    }

    private void StopManagerTree()
    {
        try
        {
            if (manager != null && !manager.HasExited)
            {
                using (var taskkill = Process.Start(new ProcessStartInfo("taskkill.exe", "/pid " + manager.Id + " /t /f") { CreateNoWindow = true, UseShellExecute = false }))
                {
                    taskkill?.WaitForExit(3000);
                }
            }
        }
        catch { }
    }

    private static string EscapeJson(string value)
    {
        return value.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "\\r").Replace("\n", "\\n");
    }
}

internal sealed class ChatForm : Form
{
    private readonly string address;
    private readonly WebView2 view = new WebView2 { Dock = DockStyle.Fill };

    internal ChatForm(string address)
    {
        this.address = address;
        Text = "DSh Chat";
        Width = 1440;
        Height = 920;
        MinimumSize = new System.Drawing.Size(960, 640);
        Controls.Add(view);
        Shown += async (_, __) =>
        {
            await view.EnsureCoreWebView2Async();
            view.CoreWebView2.Settings.AreDevToolsEnabled = false;
            view.CoreWebView2.Settings.AreDefaultContextMenusEnabled = false;
            view.CoreWebView2.NewWindowRequested += (_, args) => { args.Handled = false; };
            view.CoreWebView2.Navigate(this.address);
        };
    }
}
