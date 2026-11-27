using System;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Media.Imaging;
using Ellipse = System.Windows.Shapes.Ellipse;
using System.Windows.Automation;
using System.Windows.Threading;
using Microsoft.Win32;

namespace AntigravityBoot {
    internal class Launcher : Window {
        // Saved per-app registry indices follow this order. Append new presets at the end.
        static readonly string[] Names = { "经典版", "水彩绘本", "霓虹都市", "换班", "星门回眸" };
        static readonly string[] Files = { "gemini-classic", "gemini-watercolor", "gemini-neon", "gemini-switch-team", "gemini-stargate" };
        const string Key = @"Software\Antigravity Boot";
        readonly ComboBox apps = new ComboBox { ItemsSource = new[] { "Gemini", "Antigravity" } };
        readonly ComboBox movies = new ComboBox { ItemsSource = Names };
        internal Launcher() {
            Title = "Antigravity Boot";
            Width = 432; SizeToContent = SizeToContent.Height;
            WindowStartupLocation = WindowStartupLocation.CenterScreen;
            ResizeMode = ResizeMode.CanMinimize;
            var panel = new StackPanel { Margin = new Thickness(26) };
            Content = panel;
            panel.Children.Add(new Label { Content = "目标应用" });
            panel.Children.Add(apps);
            panel.Children.Add(new Label { Content = "启动动画", Margin = new Thickness(0,12,0,0) });
            var movieRow = new DockPanel();
            var preview = new Button { Content = "预览动画", Padding = new Thickness(10,3,10,3), Margin = new Thickness(8,0,0,0) };
            DockPanel.SetDock(preview, Dock.Right);
            movieRow.Children.Add(preview);
            movieRow.Children.Add(movies);
            panel.Children.Add(movieRow);
            panel.Children.Add(CreatorButton());
            preview.Click += delegate {
                try { PreviewMovie(SelectedMovie()); }
                catch (Exception ex) { MessageBox.Show(this, ex.Message, Title); }
            };
            var start = new Button { Content = "启动", IsDefault = true, Height = 34, Margin = new Thickness(0,22,0,0) };
            panel.Children.Add(start);
            apps.SelectionChanged += delegate { movies.SelectedIndex = ReadIndex((string)apps.SelectedItem, Names.Length); };
            apps.SelectedIndex = ReadIndex("Target", 2);
            start.Click += delegate {
                try {
                    var name = (string)apps.SelectedItem;
                    var movie = SelectedMovie();
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
        string SelectedMovie() {
            var file = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Media", "Presets", Files[movies.SelectedIndex] + ".mp4");
            if (!File.Exists(file)) throw new FileNotFoundException("缺少动画，请完整解压 ZIP 后再启动。", file);
            return file;
        }

        Window Dialog(string title, double width) {
            return new Window { Owner = this, Title = title, Width = Math.Min(width, SystemParameters.WorkArea.Width),
                SizeToContent = SizeToContent.Height, WindowStartupLocation = WindowStartupLocation.CenterOwner,
                ResizeMode = ResizeMode.NoResize, ShowInTaskbar = false };
        }

        void PreviewMovie(string file) {
            var dialog = Dialog("预览 · " + movies.SelectedItem, 580);
            var video = new MediaElement { LoadedBehavior = MediaState.Manual, Stretch = Stretch.Uniform,
                Height = Math.Min(dialog.Width * 9 / 16, SystemParameters.WorkArea.Height * .62) };
            var root = new StackPanel();
            root.Children.Add(new Border { Background = Brushes.Black, Child = video });
            var bar = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right,
                Margin = new Thickness(12) };
            var toggle = new Button { Content = "暂停", MinWidth = 76, Height = 30 };
            var back = new Button { Content = "返回设置", IsCancel = true, MinWidth = 86, Margin = new Thickness(8,0,0,0) };
            bar.Children.Add(toggle);
            bar.Children.Add(back);
            root.Children.Add(bar);
            dialog.Content = root;
            bool playing = true, ended = false;
            toggle.Click += delegate {
                if (playing) video.Pause();
                else {
                    if (ended) video.Position = TimeSpan.Zero;
                    ended = false;
                    video.Play();
                }
                playing = !playing;
                toggle.Content = playing ? "暂停" : "继续播放";
            };
            video.MediaEnded += delegate { ended = true; playing = false; toggle.Content = "重新播放"; };
            video.MediaFailed += delegate {
                if (dialog.IsVisible) {
                    MessageBox.Show(dialog, "无法预览，请检查系统媒体组件和随包 MP4。", dialog.Title);
                    dialog.Close();
                }
            };
            dialog.Loaded += delegate { video.Source = new Uri(file); video.Play(); };
            dialog.Closed += delegate { video.Close(); };
            dialog.ShowDialog();
        }

        Button CreatorButton() {
            var file = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Media", "douyin.png");
            var row = new DockPanel { LastChildFill = true };
            if (File.Exists(file)) {
                var card = new BitmapImage(new Uri(file));
                // Only the raccoon portrait from the official card is visible in settings.
                var portrait = new CroppedBitmap(card, new Int32Rect(460, 500, 296, 296));
                row.Children.Add(new Ellipse { Width = 36, Height = 36, Margin = new Thickness(0,0,10,0),
                    Fill = new ImageBrush(portrait) });
            }
            var action = new TextBlock { Text = "去支持一下  ›", Foreground = SystemColors.HotTrackBrush,
                VerticalAlignment = VerticalAlignment.Center };
            DockPanel.SetDock(action, Dock.Right);
            row.Children.Add(action);
            row.Children.Add(new TextBlock { Text = "波子哥 开源", FontSize = 16, FontWeight = FontWeights.SemiBold,
                VerticalAlignment = VerticalAlignment.Center });
            var button = new Button { Content = row, HorizontalContentAlignment = HorizontalAlignment.Stretch,
                Background = SystemColors.WindowBrush, BorderBrush = SystemColors.ControlLightBrush,
                Cursor = System.Windows.Input.Cursors.Hand, Padding = new Thickness(12,0,12,0),
                Height = 54, Margin = new Thickness(0,18,0,0) };
            AutomationProperties.SetName(button, "波子哥 开源 · 去支持一下");
            button.Click += delegate {
                try { ShowCreator(file); }
                catch (Exception ex) { MessageBox.Show(this, ex.Message, Title); }
            };
            return button;
        }

        void ShowCreator(string file) {
            var dialog = Dialog("波子哥 开源", 400);
            var root = new StackPanel { Margin = new Thickness(18) };
            root.Children.Add(new TextBlock { Text = "开源不易，喜欢这个启动器的话，来抖音关注支持一下。\n抖音号：BobbyCao",
                TextWrapping = TextWrapping.Wrap });
            if (File.Exists(file)) root.Children.Add(new Image { Source = new BitmapImage(new Uri(file)),
                Stretch = Stretch.Uniform, Height = Math.Min(390, SystemParameters.WorkArea.Height * .57), Margin = new Thickness(0,12,0,12) });
            var bar = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center };
            var open = new Button { Content = "打开抖音主页", Padding = new Thickness(12,5,12,5) };
            open.Click += delegate {
                try { Process.Start(new ProcessStartInfo("https://www.douyin.com/user/MS4wLjABAAAAqfTLdIWYEIvollbyqL6yeU2anTbgSXkD_2-N-FNuztk") { UseShellExecute = true }); }
                catch (Exception ex) { MessageBox.Show(dialog, ex.Message, dialog.Title); }
            };
            bar.Children.Add(open);
            bar.Children.Add(new Button { Content = "返回设置", IsCancel = true,
                Padding = new Thickness(12,5,12,5), Margin = new Thickness(8,0,0,0) });
            root.Children.Add(bar);
            dialog.Content = root;
            dialog.ShowDialog();
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
