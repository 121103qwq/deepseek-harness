using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;

internal static class DeepSeekConfigure
{
    private static readonly string[] ManagedPluginIds =
    {
        "deepseek-desktop-plugin-helper",
        "deepseek-desktop-update-sync",
        "deepseek-desktop-free-fallback",
        "deepseek-desktop-vision-preflight",
        "deepseek-desktop-web-diagnostics",
        "dsh-session-export",
        "dsh-mic-input",
        "auto-continue",
        "ui-attention-badge",
        "ui-model-selection",
        "vision-sidecar",
        "llm-deepseek",
        "web-search-deepseek",
        "agent-default-model",
        "llm-pi-ai",
    };

    private static string InstallRoot
    {
        get { return AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar); }
    }

    private static string DshHome
    {
        get
        {
            string configured = Environment.GetEnvironmentVariable("DSH_HOME");
            return String.IsNullOrWhiteSpace(configured)
                ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DeepSeek Harness Data")
                : Path.GetFullPath(configured);
        }
    }

    private static int Main(string[] args)
    {
        string logDirectory = Path.Combine(InstallRoot, "logs");
        Directory.CreateDirectory(logDirectory);
        string logPath = Path.Combine(logDirectory, "install-validation.log");
        try
        {
            if (args.Length != 4) throw new ArgumentException("安装配置参数不完整。");
            string model = args[0];
            if (model != "kilo" && model != "deepseek") throw new ArgumentException("未知模型路线：" + model);
            HashSet<string> selected = new HashSet<string>((args[1] ?? String.Empty).Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries), StringComparer.Ordinal);
            bool checkUpdates = ParseBoolean(args[2], "后台检查更新");
            bool autoDownload = ParseBoolean(args[3], "后台下载更新");
            Directory.CreateDirectory(DshHome);
            using (FileStream instanceLock = AcquireHomeLock(DshHome))
            {
                AppendLog(logPath, "Acquired DSH_HOME lock: " + DshHome);
                ConfigureProfile(model, selected, checkUpdates, autoDownload, logPath);
            }
            AppendLog(logPath, "Configuration and plugin-chain validation succeeded.");
            return 0;
        }
        catch (Exception error)
        {
            AppendLog(logPath, error.ToString());
            return 1;
        }
    }

    private static bool ParseBoolean(string value, string label)
    {
        bool result;
        if (!Boolean.TryParse(value, out result)) throw new ArgumentException(label + "参数无效。");
        return result;
    }

    private static void ConfigureProfile(string model, HashSet<string> selected, bool checkUpdates, bool autoDownload, string logPath)
    {
        string profileRoot = Path.Combine(DshHome, "profiles", "web");
        Directory.CreateDirectory(profileRoot);
        string defaultsPath = Path.Combine(InstallRoot, "defaults", "cordis.patch.yml");
        if (!File.Exists(defaultsPath)) throw new InvalidOperationException("安装包缺少默认 profile 配置。");
        string template = File.ReadAllText(defaultsPath, Encoding.UTF8).Replace("\r\n", "\n").Replace("\r", "\n");
        template = ConfigureTemplate(template, model, selected, checkUpdates, autoDownload);

        List<FileChange> changes = new List<FileChange>();
        string manifestPath = Path.Combine(profileRoot, "package.json");
        if (!File.Exists(manifestPath))
        {
            string manifest = "{\r\n  \"name\": \"dsh-profile-web\",\r\n  \"private\": true,\r\n  \"dependencies\": {},\r\n  \"dsh\": {\r\n    \"profile\": {\r\n      \"bundles\": [\r\n        \"@deepseek-ai/dsh-base\",\r\n        \"@deepseek-ai/dsh-web-app\"\r\n      ]\r\n    }\r\n  }\r\n}\r\n";
            changes.Add(PrepareChange(manifestPath, manifest));
        }
        string workspacePath = Path.Combine(profileRoot, "pnpm-workspace.yaml");
        if (!File.Exists(workspacePath))
        {
            changes.Add(PrepareChange(workspacePath, "packages:\r\n  - .\r\n\r\nnodeLinker: hoisted\r\nautoInstallPeers: false\r\n"));
        }
        string patchPath = Path.Combine(profileRoot, "cordis.patch.yml");
        string finalPatch = File.Exists(patchPath)
            ? MergeManagedRows(File.ReadAllText(patchPath, Encoding.UTF8), template)
            : template;
        changes.Add(PrepareChange(patchPath, NormalizeNewlines(finalPatch)));
        string settingsPath = Path.Combine(DshHome, "settings.yaml");
        if (!File.Exists(settingsPath))
        {
            changes.Add(PrepareChange(settingsPath, "ui-onboarding:\r\n  welcomeNoticeVersion: 2026-08-26.1\r\n"));
        }

        try
        {
            CommitChanges(changes);
            AppendLog(logPath, "Committed installer-owned profile rows.");
            ValidatePluginChain(selected, logPath);
            CompleteChanges(changes);
        }
        catch
        {
            RollbackChanges(changes);
            throw;
        }
    }

    private static string ConfigureTemplate(string text, string model, HashSet<string> selected, bool checkUpdates, bool autoDownload)
    {
        if (model == "deepseek")
        {
            text = text.Replace("provider: kilo\n    model: kilo-auto/free", "provider: deepseek-official\n    model: deepseek-v4-flash");
            text = SetBlockEnabled(text, "llm-deepseek", true);
            text = SetBlockEnabled(text, "web-search-deepseek", true);
        }
        else
        {
            text = SetBlockEnabled(text, "llm-deepseek", false);
            text = SetBlockEnabled(text, "web-search-deepseek", false);
        }

        string[] selectable =
        {
            "deepseek-desktop-free-fallback",
            "deepseek-desktop-vision-preflight",
            "deepseek-desktop-web-diagnostics",
            "dsh-session-export",
            "dsh-mic-input",
            "auto-continue",
            "ui-attention-badge",
            "ui-model-selection",
            "vision-sidecar",
        };
        foreach (string id in selectable)
        {
            bool enabled = selected.Contains(id);
            if (id == "deepseek-desktop-free-fallback" && model == "deepseek") enabled = false;
            text = SetBlockEnabled(text, id, enabled);
        }
        text = SetBlockEnabled(text, "deepseek-desktop-plugin-helper", true);
        text = SetBlockEnabled(text, "deepseek-desktop-update-sync", true);
        string update = GetBlock(text, "deepseek-desktop-update-sync");
        update = Regex.Replace(update, @"(?m)^\s+checkInBackground:\s*(?:true|false)\s*$", "        checkInBackground: " + checkUpdates.ToString().ToLowerInvariant());
        update = Regex.Replace(update, @"(?m)^\s+allowBackgroundAutoUpdate:\s*(?:true|false)\s*$", "        allowBackgroundAutoUpdate: " + autoDownload.ToString().ToLowerInvariant());
        return ReplaceBlock(text, "deepseek-desktop-update-sync", update);
    }

    private static string MergeManagedRows(string existing, string configuredTemplate)
    {
        string result = existing;
        foreach (string id in ManagedPluginIds)
        {
            result = UpsertBlock(result, id, GetBlock(configuredTemplate, id));
        }
        return result;
    }

    private static string SetBlockEnabled(string text, string id, bool enabled)
    {
        string block = GetBlock(text, id);
        block = Regex.Replace(block, @"(?m)^\s+disabled:\s*(?:true|false)\s*\r?\n?", String.Empty);
        string indentation = block.StartsWith("- insert:", StringComparison.Ordinal) ? "      " : "  ";
        block = block.TrimEnd() + "\n" + indentation + "disabled: " + (!enabled).ToString().ToLowerInvariant() + "\n\n";
        return ReplaceBlock(text, id, block);
    }

    private static string GetBlock(string text, string id)
    {
        Match match = Regex.Match(text, ManagedBlockPattern(id));
        if (!match.Success) throw new InvalidOperationException("默认配置缺少插件行：" + id);
        return match.Value.TrimEnd() + "\n\n";
    }

    private static string ReplaceBlock(string text, string id, string block)
    {
        Match match = Regex.Match(text, ManagedBlockPattern(id));
        if (!match.Success) throw new InvalidOperationException("配置缺少插件行：" + id);
        return text.Substring(0, match.Index) + block + text.Substring(match.Index + match.Length);
    }

    private static string UpsertBlock(string text, string id, string block)
    {
        Match match = Regex.Match(text, ManagedBlockPattern(id));
        if (!match.Success) return text.TrimEnd() + "\n\n" + block;
        return text.Substring(0, match.Index) + block + text.Substring(match.Index + match.Length);
    }

    private static string ManagedBlockPattern(string id)
    {
        string escaped = Regex.Escape(id);
        return @"(?ms)^(?:- id:\s*" + escaped + @"\s*\r?\n|- insert:\s*\r?\n    - id:\s*" + escaped + @"\s*\r?\n)(?:(?!^- ).)*";
    }

    private static string NormalizeNewlines(string text)
    {
        return text.Replace("\r\n", "\n").Replace("\r", "\n").Replace("\n", "\r\n").TrimEnd() + "\r\n";
    }

    private static FileChange PrepareChange(string target, string content)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(target));
        string temporary = target + ".desktop-install-" + Guid.NewGuid().ToString("N") + ".tmp";
        File.WriteAllText(temporary, content, new UTF8Encoding(false));
        return new FileChange(target, temporary, target + ".desktop-install.bak", File.Exists(target));
    }

    private static void CommitChanges(List<FileChange> changes)
    {
        foreach (FileChange change in changes)
        {
            if (change.Existed)
            {
                if (File.Exists(change.Backup)) File.Delete(change.Backup);
                File.Replace(change.Temporary, change.Target, change.Backup, true);
            }
            else
            {
                File.Move(change.Temporary, change.Target);
            }
            change.Committed = true;
        }
    }

    private static void CompleteChanges(List<FileChange> changes)
    {
        foreach (FileChange change in changes)
        {
            if (File.Exists(change.Backup)) File.Delete(change.Backup);
            if (File.Exists(change.Temporary)) File.Delete(change.Temporary);
        }
    }

    private static void RollbackChanges(List<FileChange> changes)
    {
        for (int index = changes.Count - 1; index >= 0; index--)
        {
            FileChange change = changes[index];
            try
            {
                if (change.Committed)
                {
                    if (change.Existed && File.Exists(change.Backup))
                    {
                        if (File.Exists(change.Target)) File.Replace(change.Backup, change.Target, null, true);
                        else File.Move(change.Backup, change.Target);
                    }
                    else if (!change.Existed && File.Exists(change.Target)) File.Delete(change.Target);
                }
                if (File.Exists(change.Temporary)) File.Delete(change.Temporary);
            }
            catch
            {
            }
        }
    }

    private static void ValidatePluginChain(HashSet<string> selected, string logPath)
    {
        string node = Path.Combine(InstallRoot, "runtime", "node.exe");
        string bin = Path.Combine(InstallRoot, "app", "node_modules", "@deepseek-ai", "dsh", "lib", "bin.js");
        if (!File.Exists(node) || !File.Exists(bin)) throw new InvalidOperationException("安装包缺少内置 Harness 运行文件。");
        int port = AllocateFreePort();
        ProcessStartInfo start = new ProcessStartInfo(node, "\"" + bin + "\" web --port " + port + " --no-open");
        start.UseShellExecute = false;
        start.CreateNoWindow = true;
        start.WorkingDirectory = InstallRoot;
        start.RedirectStandardOutput = true;
        start.RedirectStandardError = true;
        start.EnvironmentVariables["DSH_HOME"] = DshHome;
        start.EnvironmentVariables["DSH_WEB_DESKTOP"] = "1";
        start.EnvironmentVariables["LLM7_API_KEY"] = "unused";
        start.EnvironmentVariables["NODE_USE_ENV_PROXY"] = "1";
        string path = start.EnvironmentVariables["PATH"] ?? String.Empty;
        start.EnvironmentVariables["PATH"] = Path.Combine(InstallRoot, "runtime") + ";" + Path.Combine(InstallRoot, "app", "node_modules", ".bin") + ";" + path;
        using (Process process = Process.Start(start))
        {
            if (process == null) throw new InvalidOperationException("无法启动安装预检进程。");
            process.OutputDataReceived += delegate(object sender, DataReceivedEventArgs args) { AppendLog(logPath, args.Data); };
            process.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs args) { AppendLog(logPath, args.Data); };
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();
            try
            {
                DateTime deadline = DateTime.UtcNow.AddSeconds(55);
                string roster = null;
                while (DateTime.UtcNow < deadline)
                {
                    if (process.HasExited) throw new InvalidOperationException("Harness 安装预检提前退出，代码 " + process.ExitCode + "。");
                    try
                    {
                        roster = DownloadString("http://127.0.0.1:" + port + "/__deepseek_desktop/plugin-helper");
                        if (roster.Contains("\"helper\":\"deepseek-desktop-plugin-helper\"")) break;
                    }
                    catch (WebException) { }
                    Thread.Sleep(200);
                }
                if (String.IsNullOrEmpty(roster) || !roster.Contains("\"helper\":\"deepseek-desktop-plugin-helper\""))
                {
                    throw new TimeoutException("Harness 安装预检在 55 秒内没有加载桌面插件助手。");
                }
                AssertEnabledRosterPlugin(roster, "deepseek-desktop-update-sync");
                foreach (string id in selected)
                {
                    AssertEnabledRosterPlugin(roster, id);
                }
            }
            finally
            {
                try
                {
                    if (!process.HasExited)
                    {
                        process.Kill();
                        process.WaitForExit(5000);
                    }
                }
                catch
                {
                }
            }
        }
    }

    private static void AssertEnabledRosterPlugin(string roster, string id)
    {
        string enabledPlugin = "\"id\":\"" + id + "\",\"name\":";
        int pluginIndex = roster.IndexOf(enabledPlugin, StringComparison.Ordinal);
        if (pluginIndex < 0) throw new InvalidOperationException("插件未进入 Harness profile：" + id);
        int enabledIndex = roster.IndexOf("\"enabled\":true", pluginIndex, StringComparison.Ordinal);
        int nextPluginIndex = roster.IndexOf("\"id\":", pluginIndex + enabledPlugin.Length, StringComparison.Ordinal);
        if (enabledIndex < 0 || (nextPluginIndex >= 0 && enabledIndex > nextPluginIndex))
        {
            throw new InvalidOperationException("插件未在安装预检中启用：" + id);
        }
    }

    private static bool CanConnect(int port)
    {
        try
        {
            using (TcpClient client = new TcpClient())
            {
                IAsyncResult pending = client.BeginConnect(IPAddress.Loopback, port, null, null);
                if (!pending.AsyncWaitHandle.WaitOne(350)) return false;
                client.EndConnect(pending);
                return true;
            }
        }
        catch
        {
            return false;
        }
    }

    private static string DownloadString(string url)
    {
        HttpWebRequest request = (HttpWebRequest)WebRequest.Create(url);
        request.Timeout = 5000;
        request.ReadWriteTimeout = 5000;
        using (HttpWebResponse response = (HttpWebResponse)request.GetResponse())
        using (Stream stream = response.GetResponseStream())
        using (StreamReader reader = new StreamReader(stream, Encoding.UTF8))
        {
            return reader.ReadToEnd();
        }
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
            throw new InvalidOperationException("DSH_HOME 正在被 DeepSeek Desktop 或 DSH Launcher 使用，请关闭后重试安装。", error);
        }
    }

    private static void AppendLog(string path, string message)
    {
        if (String.IsNullOrEmpty(message)) return;
        try { File.AppendAllText(path, DateTime.Now.ToString("O") + " " + message + Environment.NewLine, new UTF8Encoding(false)); }
        catch { }
    }

    private sealed class FileChange
    {
        internal FileChange(string target, string temporary, string backup, bool existed)
        {
            Target = target;
            Temporary = temporary;
            Backup = backup;
            Existed = existed;
        }

        internal readonly string Target;
        internal readonly string Temporary;
        internal readonly string Backup;
        internal readonly bool Existed;
        internal bool Committed;
    }
}
