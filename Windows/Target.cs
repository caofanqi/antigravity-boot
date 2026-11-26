using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Management;
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace AntigravityBoot {
    internal sealed class Target {
        internal readonly string Exe;
        readonly string profile;
        Target(string exe, string browserProfile) { Exe = exe; profile = browserProfile; }

        internal static Target Resolve(string name) {
            var roots = new[] {
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs"),
                Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
                Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86)
            };
            string file = name + ".exe";
            var candidates = roots.Select(root => Path.Combine(root, name, file)).ToList();
            foreach (var hive in new[] { Registry.CurrentUser, Registry.LocalMachine }) {
                using (var key = hive.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\App Paths\" + file)) {
                    if (key != null && key.GetValue(null) is string)
                        candidates.Insert(0, ((string)key.GetValue(null)).Trim('"'));
                }
            }
            string installed = candidates.FirstOrDefault(File.Exists);
            if (installed != null) return new Target(installed, null);
            if (name == "Antigravity") {
                var pick = new OpenFileDialog { Title = "找到已安装的 Antigravity.exe", Filter = "Antigravity|Antigravity.exe" };
                if (pick.ShowDialog() != true) return null;
                if (!String.Equals(Path.GetFileName(pick.FileName), file, StringComparison.OrdinalIgnoreCase))
                    throw new IOException("请选择 Antigravity.exe。");
                return new Target(pick.FileName, null);
            }
            var edge = roots.Concat(new[] { Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData) })
                .Select(root => Path.Combine(root, @"Microsoft\Edge\Application\msedge.exe")).FirstOrDefault(File.Exists);
            if (edge == null) throw new IOException("未找到 Gemini 或 Microsoft Edge。请先安装其中一个，再启动 Gemini。");
            return new Target(edge, Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                @"Antigravity Boot\Gemini Browser"));
        }

        internal void Launch() {
            var args = profile == null ? "" : "--user-data-dir=\"" + profile + "\" --no-first-run --app=https://gemini.google.com/app";
            using (Process.Start(new ProcessStartInfo(Exe, args) { UseShellExecute = false })) {}
        }

        // Called on a worker thread. Match the executable and (for Edge) our private app profile.
        internal IntPtr FindWindow() {
            var ids = new HashSet<int>();
            if (profile != null) {
                using (var query = new ManagementObjectSearcher("SELECT ProcessId,ExecutablePath,CommandLine FROM Win32_Process WHERE Name='msedge.exe'"))
                using (var rows = query.Get()) {
                    foreach (ManagementObject row in rows) using (row) {
                        var cmd = row["CommandLine"] as string ?? "";
                        if (String.Equals(row["ExecutablePath"] as string, Exe, StringComparison.OrdinalIgnoreCase) &&
                            cmd.IndexOf("--user-data-dir=\"" + profile + "\"", StringComparison.OrdinalIgnoreCase) >= 0)
                            ids.Add(Convert.ToInt32(row["ProcessId"]));
                    }
                }
            } else {
                foreach (var process in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(Exe))) using (process) {
                    try {
                        if (String.Equals(process.MainModule.FileName, Exe, StringComparison.OrdinalIgnoreCase)) ids.Add(process.Id);
                    } catch (InvalidOperationException) {} catch (System.ComponentModel.Win32Exception) {}
                }
            }
            IntPtr result = IntPtr.Zero;
            Native.EnumWindows(delegate(IntPtr h, IntPtr unused) {
                int pid;
                Native.GetWindowThreadProcessId(h, out pid);
                Native.Rect box;
                if (ids.Contains(pid) && Native.IsWindowVisible(h) && Native.GetWindow(h, 4) == IntPtr.Zero &&
                    Native.GetWindowTextLength(h) > 0 && Native.GetWindowRect(h, out box) &&
                    (Native.IsIconic(h) || (box.Right-box.Left >= 280 && box.Bottom-box.Top >= 160))) {
                    result = h;
                    return false;
                }
                return true;
            }, IntPtr.Zero);
            return result;
        }
    }

    internal static class Native {
        internal delegate bool Visit(IntPtr h, IntPtr arg);
        [StructLayout(LayoutKind.Sequential)] internal struct Rect { internal int Left, Top, Right, Bottom; }
        [DllImport("user32")] internal static extern bool EnumWindows(Visit cb, IntPtr arg);
        [DllImport("user32")] internal static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
        [DllImport("user32")] internal static extern bool IsWindowVisible(IntPtr h);
        [DllImport("user32")] internal static extern bool IsIconic(IntPtr h);
        [DllImport("user32")] internal static extern IntPtr GetWindow(IntPtr h, uint cmd);
        [DllImport("user32", CharSet=CharSet.Unicode)] internal static extern int GetWindowTextLength(IntPtr h);
        [DllImport("user32")] internal static extern bool GetWindowRect(IntPtr h, out Rect rect);
        [DllImport("user32")] internal static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int height, uint flags);
        [DllImport("user32")] internal static extern bool ShowWindowAsync(IntPtr h, int cmd);
        [DllImport("user32")] internal static extern bool SetForegroundWindow(IntPtr h);
        [DllImport("user32")] internal static extern IntPtr GetForegroundWindow();
        [DllImport("user32")] internal static extern short GetAsyncKeyState(int key);
        [DllImport("user32")] internal static extern int GetWindowLong(IntPtr h, int index);
        [DllImport("user32")] internal static extern int SetWindowLong(IntPtr h, int index, int value);
        [DllImport("user32")] internal static extern bool SetLayeredWindowAttributes(IntPtr h, uint color, byte alpha, uint flags);
    }
}
