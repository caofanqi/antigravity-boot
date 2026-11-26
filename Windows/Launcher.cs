using System;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Threading;
using Microsoft.Win32;

namespace AntigravityBoot {
    internal class Launcher : Window {
        static readonly string[] Names = { "经典版", "水彩绘本", "霓虹都市", "换班" };
        static readonly string[] Files = { "gemini-classic", "gemini-watercolor", "gemini-neon", "gemini-switch-team" };
        const string Key = @"Software\Antigravity Boot";
        readonly ComboBox apps = new ComboBox { ItemsSource = new[] { "Gemini", "Antigravity" } };
        readonly ComboBox movies = new ComboBox { ItemsSource = Names };
        internal Launcher() {
            Title = "Antigravity Boot";
            Width = 360; SizeToContent = SizeToContent.Height;
            WindowStartupLocation = WindowStartupLocation.CenterScreen;
            ResizeMode = ResizeMode.CanMinimize;
            var panel = new StackPanel { Margin = new Thickness(26) };
            Content = panel;
            panel.Children.Add(new Label { Content = "目标应用" });
            panel.Children.Add(apps);
            panel.Children.Add(new Label { Content = "启动动画", Margin = new Thickness(0,12,0,0) });
            panel.Children.Add(movies);
            var start = new Button { Content = "启动", IsDefault = true, Height = 34, Margin = new Thickness(0,22,0,0) };
            panel.Children.Add(start);
            apps.SelectionChanged += delegate { movies.SelectedIndex = ReadIndex((string)apps.SelectedItem, Names.Length); };
            apps.SelectedIndex = ReadIndex("Target", 2);
            start.Click += delegate {
                try {
                    var name = (string)apps.SelectedItem;
                    var movie = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Media", "Presets", Files[movies.SelectedIndex] + ".mp4");
                    if (!File.Exists(movie)) throw new FileNotFoundException("缺少动画，请完整解压 ZIP 后再启动。", movie);
                    var target = Target.Resolve(name);
                    if (target == null) return;
                    using (var key = Registry.CurrentUser.CreateSubKey(Key)) {
                        key.SetValue("Target", apps.SelectedIndex);
                        key.SetValue(name, movies.SelectedIndex);
                    }
                    var player = new Playback(target, movie);
                    target.Launch();
                    player.Show();
                    Close();
                } catch (Exception ex) { MessageBox.Show(this, ex.Message, Title); }
            };
        }
        static int ReadIndex(string field, int count) {
            using (var key = Registry.CurrentUser.OpenSubKey(Key)) {
                var value = key == null ? null : key.GetValue(field);
                return value is int && (int)value >= 0 && (int)value < count ? (int)value : 0;
            }
        }
        [STAThread] public static void Main() { new Application().Run(new Launcher()); }
    }

    internal sealed class Playback : Window {
        readonly MediaPlayer media = new MediaPlayer();
        readonly DispatcherTimer timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(25) };
        readonly Stopwatch elapsed = new Stopwatch();
        readonly Target target;
        readonly Button skip = new Button { Content = "跳过  Esc", Padding = new Thickness(14,5,14,5),
            Margin = new Thickness(16), HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Bottom };
        IntPtr hwnd, destination;
        bool searching, closed, waiting, fading;
        double nextSearch, waitStarted, fadeStarted, fadeLength;
        const double Tail = 1.25;

        internal Playback(Target target, string movie) {
            this.target = target;
            WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize;
            Topmost = true; Background = Brushes.Black;
            Width = Math.Min(1100, SystemParameters.WorkArea.Width * .9); Height = Width * 9 / 16;
            WindowStartupLocation = WindowStartupLocation.CenterScreen;
            var canvas = new Grid { ClipToBounds = true };
            Content = canvas;
            var frame = new VideoDrawing { Player = media, Rect = new Rect(0,0,16,9) };
            canvas.Children.Add(new System.Windows.Shapes.Rectangle { Fill = new DrawingBrush(frame) { Stretch = Stretch.UniformToFill },
                Effect = new BlurEffect { Radius = 18 }, RenderTransformOrigin = new Point(.5,.5), RenderTransform = new ScaleTransform(1.08,1.08) });
            canvas.Children.Add(new System.Windows.Shapes.Rectangle { Fill = new DrawingBrush(frame) { Stretch = Stretch.Uniform } });
            canvas.Children.Add(skip);
            skip.Click += delegate { Finish(); };
            PreviewKeyDown += delegate(object sender, System.Windows.Input.KeyEventArgs e) {
                if (e.Key == System.Windows.Input.Key.Escape) { e.Handled = true; Finish(); }
            };
            media.MediaFailed += delegate { if (!closed) { Finish(); MessageBox.Show("无法播放动画，请检查系统媒体组件和随包 MP4。", "Antigravity Boot"); } };
            media.MediaEnded += delegate { if (!fading && !closed) BeginFade(.35); };
            Loaded += delegate {
                hwnd = new WindowInteropHelper(this).Handle;
                elapsed.Start(); media.Open(new Uri(movie)); media.Play(); timer.Start();
            };
            timer.Tick += Tick;
            Closed += delegate { closed = true; timer.Stop(); media.Close(); FocusTarget(); };
        }

        async void Locate() {
            searching = true;
            try {
                var found = await Task.Run(() => target.FindWindow());
                if (!closed && found != IntPtr.Zero) {
                    destination = found;
                    if (Native.IsIconic(found)) Native.ShowWindowAsync(found, 9);
                    FocusTarget();
                }
            } catch (System.Management.ManagementException) {} catch (UnauthorizedAccessException) {}
            finally { searching = false; }
        }

        void FocusTarget() {
            if (destination != IntPtr.Zero && Native.IsWindowVisible(destination))
                Native.SetForegroundWindow(destination);
        }

        void Tick(object sender, EventArgs args) {
            double now = elapsed.Elapsed.TotalSeconds;
            if (destination != IntPtr.Zero && !Native.IsWindowVisible(destination)) destination = IntPtr.Zero;
            if (destination == IntPtr.Zero && !searching && now >= nextSearch) {
                nextSearch = now + .55;
                Locate();
            }
            if (destination != IntPtr.Zero) {
                Native.Rect rect;
                if (!Native.IsIconic(destination) && Native.GetWindowRect(destination, out rect))
                    Native.SetWindowPos(hwnd, IntPtr.Zero, rect.Left, rect.Top, rect.Right-rect.Left, rect.Bottom-rect.Top, 0x14);
                if (Native.GetForegroundWindow() == destination && Native.GetAsyncKeyState(0x1B) < 0) { Finish(); return; }
            }
            if (fading) {
                var t = Math.Min(1, (now-fadeStarted)/fadeLength);
                var opacity = 1-t*t*(3-2*t);
                Native.SetLayeredWindowAttributes(hwnd, 0, (byte)(255*opacity), 2);
                media.Volume = .5*opacity;
                if (t >= 1) Finish();
                return;
            }
            bool atTail = media.NaturalDuration.HasTimeSpan &&
                media.Position >= media.NaturalDuration.TimeSpan - TimeSpan.FromSeconds(Tail);
            if (waiting || atTail) {
                if (destination != IntPtr.Zero || (waiting && now - waitStarted >= 10)) {
                    media.Play();
                    BeginFade(Tail);
                } else if (!waiting) {
                    waiting = true;
                    waitStarted = now;
                    media.Pause();
                    skip.Content = "正在等待应用…  跳过";
                }
            } else if (now >= 30) BeginFade(.35);
        }

        void BeginFade(double seconds) {
            fading = true; fadeStarted = elapsed.Elapsed.TotalSeconds; fadeLength = seconds;
            skip.Visibility = Visibility.Hidden;
            Native.SetWindowLong(hwnd, -20, Native.GetWindowLong(hwnd, -20) | 0x80000);
            Native.SetLayeredWindowAttributes(hwnd, 0, 255, 2);
            FocusTarget();
        }
        void Finish() { if (!closed) Close(); }
    }
}
