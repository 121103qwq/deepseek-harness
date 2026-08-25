using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

[assembly: AssemblyTitle("DeepSeek Desktop")]
[assembly: AssemblyProduct("DeepSeek Desktop")]
[assembly: AssemblyCompany("DeepSeek Desktop Community (Unofficial)")]
[assembly: AssemblyDescription("Unofficial community desktop wrapper for DeepSeek Harness")]
[assembly: AssemblyVersion("__DESKTOP_VERSION__.0")]
[assembly: AssemblyFileVersion("__DESKTOP_VERSION__.0")]
[assembly: AssemblyInformationalVersion("__DESKTOP_VERSION__")]

internal static class DeepSeekDesktop
{
    [DllImport("shell32.dll", SetLastError = true)]
    private static extern void SetCurrentProcessExplicitAppUserModelID([MarshalAs(UnmanagedType.LPWStr)] string appId);

    [STAThread]
    private static void Main()
    {
        SetCurrentProcessExplicitAppUserModelID("DeepSeek.Community.DeepSeekDesktop");
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new DesktopForm());
    }
}

internal sealed class DesktopForm : Form
{
    private const string DesktopVersion = "__DESKTOP_VERSION__";
    private const string CloseTray = "tray";
    private const string CloseExit = "exit";
    private readonly WebView2 view = new WebView2 { Dock = DockStyle.Fill, Visible = false };
    private readonly Panel loading = new Panel { Dock = DockStyle.Fill, BackColor = Color.FromArgb(8, 18, 36) };
    private readonly ProgressBar loadingBar = new ProgressBar { Style = ProgressBarStyle.Marquee, MarqueeAnimationSpeed = 24 };
    private readonly Label loadingTitle = new Label();
    private readonly Label loadingDetail = new Label();
    private Process server;
    private FileStream homeLock;
    private NotifyIcon trayIcon;
    private IntPtr serverJob = IntPtr.Zero;
    private string serverLogPath;
    private string closeBehavior;
    private int port;
    private bool started;
    private bool exiting;
    private bool navigationDiagnosticShown;

    internal DesktopForm()
    {
        Text = "DeepSeek Desktop";
        Width = 1440;
        Height = 920;
        MinimumSize = new Size(960, 640);
        StartPosition = FormStartPosition.CenterScreen;
        BackColor = Color.FromArgb(8, 18, 36);
        LoadApplicationIcon();
        BuildLoadingView();
        Controls.Add(view);
        Controls.Add(loading);
        FormClosing += OnFormClosing;
        FormClosed += OnFormClosed;
        Shown += async delegate { await StartAsync(); };
    }

    private string DshHome
    {
        get
        {
            string configured = Environment.GetEnvironmentVariable("DSH_HOME");
            return String.IsNullOrWhiteSpace(configured)
                ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DeepSeek Harness Data")
                : Path.GetFullPath(configured);
        }
    }

    private string SettingsPath
    {
        get { return Path.Combine(DshHome, "desktop-settings.json"); }
    }

    private void BuildLoadingView()
    {
        loadingTitle.AutoSize = true;
        loadingTitle.Text = "DeepSeek Desktop";
        loadingTitle.ForeColor = Color.White;
        loadingTitle.Font = new Font("Microsoft YaHei UI", 24, FontStyle.Bold);
        loadingTitle.Location = new Point(52, 58);
        loadingDetail.AutoSize = true;
        loadingDetail.Text = "正在启动内置 DeepSeek Harness…";
        loadingDetail.ForeColor = Color.FromArgb(158, 196, 255);
        loadingDetail.Font = new Font("Microsoft YaHei UI", 11, FontStyle.Regular);
        loadingDetail.Location = new Point(56, 116);
        loadingBar.Location = new Point(58, 164);
        loadingBar.Size = new Size(420, 9);
        loading.Controls.Add(loadingTitle);
        loading.Controls.Add(loadingDetail);
        loading.Controls.Add(loadingBar);
    }

    private async Task StartAsync()
    {
        if (started) return;
        started = true;
        try
        {
            Directory.CreateDirectory(DshHome);
            homeLock = AcquireHomeLock(DshHome);
            closeBehavior = ReadCloseBehavior();
            port = AllocateFreePort();
            StartServer();
            loadingDetail.Text = "本地服务正在加载，首次启动可能需要几秒…";
            Task webViewTask = view.EnsureCoreWebView2Async();
            await WaitForServerAsync();
            await webViewTask;
            ConfigureWebView();
            view.Visible = true;
            loading.Visible = false;
            view.CoreWebView2.Navigate("http://127.0.0.1:" + port);
        }
        catch (Exception error)
        {
            ShowStartupDiagnostics(error);
            exiting = true;
            Close();
        }
    }

    private void ConfigureWebView()
    {
        view.CoreWebView2.Settings.AreDevToolsEnabled = false;
        view.CoreWebView2.Settings.AreDefaultContextMenusEnabled = false;
        view.CoreWebView2.Settings.IsStatusBarEnabled = false;
        view.NavigationCompleted += OnNavigationCompleted;
        view.CoreWebView2.ProcessFailed += OnWebViewProcessFailed;
    }

    private void StartServer()
    {
        string root = AppDomain.CurrentDomain.BaseDirectory;
        string node = Path.Combine(root, "runtime", "node.exe");
        string bin = Path.Combine(root, "app", "node_modules", "@deepseek-ai", "dsh", "lib", "bin.js");
        if (!File.Exists(node) || !File.Exists(bin))
        {
            throw new InvalidOperationException("安装文件不完整，请重新安装 DeepSeek Desktop。");
        }
        string logDirectory = Path.Combine(DshHome, "logs");
        Directory.CreateDirectory(logDirectory);
        serverLogPath = Path.Combine(logDirectory, "desktop-harness.log");
        File.AppendAllText(serverLogPath, Environment.NewLine + "--- DeepSeek Desktop " + DesktopVersion + " start " + DateTime.Now.ToString("O") + " ---" + Environment.NewLine);
        ProcessStartInfo start = new ProcessStartInfo(node, "\"" + bin + "\" web --port " + port + " --no-open");
        start.UseShellExecute = false;
        start.CreateNoWindow = true;
        start.WorkingDirectory = root;
        start.RedirectStandardOutput = true;
        start.RedirectStandardError = true;
        start.EnvironmentVariables["DSH_HOME"] = DshHome;
        start.EnvironmentVariables["DSH_WEB_DESKTOP"] = "1";
        start.EnvironmentVariables["DEEPSEEK_DESKTOP_VERSION"] = DesktopVersion;
        start.EnvironmentVariables["LLM7_API_KEY"] = "unused";
        start.EnvironmentVariables["NODE_USE_ENV_PROXY"] = "1";
        string path = start.EnvironmentVariables["PATH"] ?? String.Empty;
        start.EnvironmentVariables["PATH"] = Path.Combine(root, "runtime") + ";" + Path.Combine(root, "app", "node_modules", ".bin") + ";" + path;
        server = Process.Start(start);
        if (server == null) throw new InvalidOperationException("无法启动内置 Harness 服务。");
        AssignServerToJob(server);
        server.OutputDataReceived += delegate(object sender, DataReceivedEventArgs args) { AppendServerLog(args.Data); };
        server.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs args) { AppendServerLog(args.Data); };
        server.BeginOutputReadLine();
        server.BeginErrorReadLine();
    }

    private async Task WaitForServerAsync()
    {
        DateTime deadline = DateTime.UtcNow.AddSeconds(45);
        while (DateTime.UtcNow < deadline)
        {
            if (server != null && server.HasExited)
            {
                throw new InvalidOperationException("内置 Harness 服务提前退出，代码 " + server.ExitCode + "。");
            }
            try
            {
                using (TcpClient client = new TcpClient())
                {
                    Task connection = client.ConnectAsync(IPAddress.Loopback, port);
                    Task finished = await Task.WhenAny(connection, Task.Delay(600));
                    if (finished == connection && client.Connected) return;
                }
            }
            catch (SocketException)
            {
            }
            await Task.Delay(180);
        }
        throw new TimeoutException("内置 Harness 服务在 45 秒内没有响应。");
    }

    private static int AllocateFreePort()
    {
        TcpListener listener = new TcpListener(IPAddress.Loopback, 0);
        try
        {
            listener.Start();
            return ((IPEndPoint)listener.LocalEndpoint).Port;
        }
        finally
        {
            listener.Stop();
        }
    }

    private static FileStream AcquireHomeLock(string dshHome)
    {
        string normalized = Path.GetFullPath(dshHome).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar).ToUpperInvariant();
        string localData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        string lockDirectory = String.IsNullOrWhiteSpace(localData)
            ? Path.Combine(Path.GetTempPath(), "DSH Launcher", "locks")
            : Path.Combine(localData, "DeepSeek", "launcher", "locks");
        byte[] digest;
        using (SHA256 sha = SHA256.Create()) digest = sha.ComputeHash(Encoding.UTF8.GetBytes(normalized));
        StringBuilder name = new StringBuilder(digest.Length * 2);
        foreach (byte value in digest) name.Append(value.ToString("X2"));
        Directory.CreateDirectory(lockDirectory);
        try
        {
            return new FileStream(Path.Combine(lockDirectory, name + ".lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None, 1, FileOptions.DeleteOnClose);
        }
        catch (IOException error)
        {
            throw new InvalidOperationException("同一个 DSH_HOME 已被 DeepSeek Desktop 或 DSH Launcher 使用。请先关闭另一个实例。", error);
        }
    }

    private void OnFormClosing(object sender, FormClosingEventArgs args)
    {
        if (!exiting && args.CloseReason == CloseReason.UserClosing)
        {
            if (String.IsNullOrEmpty(closeBehavior))
            {
                DialogResult choice = MessageBox.Show(
                    "以后点击关闭按钮时：\r\n\r\n选择“是”：最小化到系统托盘并记住\r\n选择“否”：直接退出并记住\r\n选择“取消”：保持窗口打开",
                    "第一次关闭时选择",
                    MessageBoxButtons.YesNoCancel,
                    MessageBoxIcon.Question,
                    MessageBoxDefaultButton.Button1);
                if (choice == DialogResult.Cancel)
                {
                    args.Cancel = true;
                    return;
                }
                closeBehavior = choice == DialogResult.Yes ? CloseTray : CloseExit;
                WriteCloseBehavior(closeBehavior);
            }
            if (closeBehavior == CloseTray)
            {
                args.Cancel = true;
                HideToTray();
                return;
            }
        }
        exiting = true;
        if (!TryStopServer())
        {
            args.Cancel = true;
            exiting = false;
            MessageBox.Show("内置 Harness 服务没有完全关闭。窗口将保持打开，以免释放 DSH_HOME 锁后留下仍在运行的进程。", "DeepSeek Desktop", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }

    private void HideToTray()
    {
        EnsureTrayIcon();
        ShowInTaskbar = false;
        Hide();
        trayIcon.Visible = true;
        trayIcon.ShowBalloonTip(1800, "DeepSeek Desktop", "程序仍在系统托盘运行。双击图标可恢复窗口。", ToolTipIcon.Info);
    }

    private void EnsureTrayIcon()
    {
        if (trayIcon != null) return;
        ContextMenuStrip menu = new ContextMenuStrip();
        menu.Items.Add("打开 DeepSeek Desktop", null, delegate { RestoreFromTray(); });
        menu.Items.Add("下次关闭时重新选择", null, delegate
        {
            closeBehavior = null;
            WriteCloseBehavior(null);
            RestoreFromTray();
        });
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("退出", null, delegate
        {
            exiting = true;
            RestoreFromTray();
            Close();
        });
        trayIcon = new NotifyIcon();
        trayIcon.Text = "DeepSeek Desktop";
        trayIcon.Icon = Icon;
        trayIcon.ContextMenuStrip = menu;
        trayIcon.DoubleClick += delegate { RestoreFromTray(); };
    }

    private void RestoreFromTray()
    {
        if (trayIcon != null) trayIcon.Visible = false;
        ShowInTaskbar = true;
        Show();
        WindowState = FormWindowState.Normal;
        Activate();
    }

    private string ReadCloseBehavior()
    {
        try
        {
            if (!File.Exists(SettingsPath)) return null;
            Match match = Regex.Match(File.ReadAllText(SettingsPath), "\\\"closeBehavior\\\"\\s*:\\s*\\\"(tray|exit)\\\"");
            return match.Success ? match.Groups[1].Value : null;
        }
        catch
        {
            return null;
        }
    }

    private void WriteCloseBehavior(string value)
    {
        try
        {
            Directory.CreateDirectory(DshHome);
            string json = value == null ? "{}\r\n" : "{\r\n  \"closeBehavior\": \"" + value + "\"\r\n}\r\n";
            string temporary = SettingsPath + ".tmp";
            File.WriteAllText(temporary, json, new UTF8Encoding(false));
            if (File.Exists(SettingsPath)) File.Replace(temporary, SettingsPath, null, true);
            else File.Move(temporary, SettingsPath);
        }
        catch
        {
            MessageBox.Show("无法保存关闭方式；下次关闭时会再次询问。", "DeepSeek Desktop", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }

    private bool TryStopServer()
    {
        if (server == null || server.HasExited) return true;
        try
        {
            if (serverJob != IntPtr.Zero)
            {
                CloseHandle(serverJob);
                serverJob = IntPtr.Zero;
            }
            if (server.WaitForExit(5000)) return true;
            server.Kill();
            return server.WaitForExit(5000);
        }
        catch
        {
            return server.HasExited;
        }
    }

    private void OnFormClosed(object sender, FormClosedEventArgs args)
    {
        if (trayIcon != null)
        {
            trayIcon.Visible = false;
            trayIcon.Dispose();
        }
        if (server != null) server.Dispose();
        if (serverJob != IntPtr.Zero) CloseHandle(serverJob);
        if (homeLock != null) homeLock.Dispose();
    }

    private void LoadApplicationIcon()
    {
        string iconPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "DeepSeek Desktop.ico");
        if (File.Exists(iconPath)) Icon = new Icon(iconPath);
    }

    private void AppendServerLog(string line)
    {
        if (String.IsNullOrEmpty(line) || String.IsNullOrEmpty(serverLogPath)) return;
        try { File.AppendAllText(serverLogPath, DateTime.Now.ToString("O") + " " + line + Environment.NewLine); }
        catch { }
    }

    private void ShowStartupDiagnostics(Exception error)
    {
        string log = String.IsNullOrEmpty(serverLogPath) ? "未创建（服务尚未启动）" : serverLogPath;
        MessageBox.Show(
            "DeepSeek Desktop 无法启动内置 Harness。\r\n\r\n本地端口：" + (port == 0 ? "尚未分配" : port.ToString()) + "\r\n服务日志：" + log + "\r\n\r\n错误：" + error.Message,
            "DeepSeek Desktop 启动诊断",
            MessageBoxButtons.OK,
            MessageBoxIcon.Error);
    }

    private void OnNavigationCompleted(object sender, CoreWebView2NavigationCompletedEventArgs args)
    {
        if (args.IsSuccess || navigationDiagnosticShown) return;
        navigationDiagnosticShown = true;
        string html = "<html><head><meta charset='utf-8'><style>body{font-family:Segoe UI,Microsoft YaHei,sans-serif;background:#081224;color:#e7f0ff;padding:42px}h1{color:#70a7ff}code{color:#a8c9ff}</style></head><body><h1>DeepSeek Desktop 本地连接诊断</h1><p>内置 WebView 无法加载 Harness 页面。</p><p>本地地址：<code>http://127.0.0.1:" + port + "</code></p><p>服务日志：<code>" + EscapeHtml(serverLogPath) + "</code></p><p>WebView 状态：<code>" + EscapeHtml(args.WebErrorStatus.ToString()) + "</code></p></body></html>";
        view.NavigateToString(html);
    }

    private void OnWebViewProcessFailed(object sender, CoreWebView2ProcessFailedEventArgs args)
    {
        if (navigationDiagnosticShown) return;
        navigationDiagnosticShown = true;
        MessageBox.Show("内置 WebView 进程异常退出：" + args.ProcessFailedKind + "\r\n\r\n服务日志：" + serverLogPath, "DeepSeek Desktop WebView 诊断", MessageBoxButtons.OK, MessageBoxIcon.Error);
    }

    private static string EscapeHtml(string value)
    {
        if (String.IsNullOrEmpty(value)) return String.Empty;
        return value.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace("\"", "&quot;");
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateJobObject(IntPtr attributes, string name);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetInformationJobObject(IntPtr job, int infoClass, IntPtr info, uint length);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);

    [StructLayout(LayoutKind.Sequential)]
    private struct JobObjectBasicLimitInformation
    {
        public long PerProcessUserTimeLimit;
        public long PerJobUserTimeLimit;
        public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize;
        public UIntPtr MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint PriorityClass;
        public uint SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct IoCounters
    {
        public ulong ReadOperationCount;
        public ulong WriteOperationCount;
        public ulong OtherOperationCount;
        public ulong ReadTransferCount;
        public ulong WriteTransferCount;
        public ulong OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct JobObjectExtendedLimitInformation
    {
        public JobObjectBasicLimitInformation BasicLimitInformation;
        public IoCounters IoInfo;
        public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed;
        public UIntPtr PeakJobMemoryUsed;
    }

    private void AssignServerToJob(Process process)
    {
        IntPtr job = CreateJobObject(IntPtr.Zero, null);
        if (job == IntPtr.Zero) throw new InvalidOperationException("无法创建 Harness 进程作业对象。");
        JobObjectExtendedLimitInformation limits = new JobObjectExtendedLimitInformation();
        limits.BasicLimitInformation.LimitFlags = 0x00002000;
        int size = Marshal.SizeOf(typeof(JobObjectExtendedLimitInformation));
        IntPtr pointer = Marshal.AllocHGlobal(size);
        try
        {
            Marshal.StructureToPtr(limits, pointer, false);
            if (!SetInformationJobObject(job, 9, pointer, (uint)size) || !AssignProcessToJobObject(job, process.Handle))
            {
                throw new InvalidOperationException("无法将 Harness 进程纳入受控作业对象。");
            }
            serverJob = job;
            job = IntPtr.Zero;
        }
        finally
        {
            Marshal.FreeHGlobal(pointer);
            if (job != IntPtr.Zero) CloseHandle(job);
        }
    }
}
