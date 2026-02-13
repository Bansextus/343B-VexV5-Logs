using Microsoft.Win32;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Tahera {
    public partial class MainWindow : Window {
        private const string RepoSettingsPassword = "56Wrenches.782";
        private const double ReplayFieldSizeIn = 144.0;
        private const double ReplayTrackWidthIn = 12.0;
        private const double ReplayMaxSpeedInPerS = 60.0;
        private const double ReplayDtFallback = 0.02;

        private bool _repoUnlocked = false;
        private bool _suppressReplaySliderEvent = false;
        private readonly List<ReplayPose> _replayPoses = new();

        private readonly Dictionary<string, (string path, int slot)> _projects = new() {
            { "The Tahera Sequence", ("Pros projects/Tahera_Project", 1) },
            { "Auton Planner", ("Pros projects/Auton_Planner_PROS", 2) },
            { "Image Selector", ("Pros projects/Jerkbot_Image_Test", 3) },
            { "Basic Bonkers", ("Pros projects/Basic_Bonkers_PROS", 4) }
        };

        public MainWindow() {
            InitializeComponent();
            RepoPathTextBox.Text = @"C:\Users\Public\GitHub\2026-Vex-V5-Pushback-Code-and-Desighn-";
            ProjectComboBox.ItemsSource = _projects.Keys;
            ProjectComboBox.SelectedIndex = 0;
            ShowSection("Home");

            LoadReadme();
            LoadReadmeLogo();
            LoadFieldImage();
            ResetReplayState("Load a replay log (.txt or .csv) to visualize path data.");
        }

        private string RepoPath => RepoPathTextBox.Text.Trim();

        private async Task<(int code, string output)> RunCommandAsync(
            string fileName,
            IEnumerable<string> args,
            string? workingDirectory = null,
            int timeoutSeconds = 180,
            bool nonInteractive = false
        ) {
            var psi = new ProcessStartInfo(fileName) {
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                RedirectStandardInput = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            foreach (var arg in args) {
                psi.ArgumentList.Add(arg);
            }

            if (!string.IsNullOrWhiteSpace(workingDirectory)) {
                psi.WorkingDirectory = workingDirectory;
            }
            if (nonInteractive) {
                // Avoid hangs from credential/password prompts in GUI workflows.
                psi.Environment["GIT_TERMINAL_PROMPT"] = "0";
                psi.Environment["GCM_INTERACTIVE"] = "Never";
                psi.Environment["GH_PROMPT_DISABLED"] = "1";
                psi.Environment["CI"] = "1";
            }

            var sb = new StringBuilder();
            using var p = new Process { StartInfo = psi };
            p.OutputDataReceived += (_, e) => { if (e.Data != null) sb.AppendLine(e.Data); };
            p.ErrorDataReceived += (_, e) => { if (e.Data != null) sb.AppendLine(e.Data); };

            p.Start();
            p.StandardInput.Close();
            p.BeginOutputReadLine();
            p.BeginErrorReadLine();
            var waitTask = p.WaitForExitAsync();
            var completed = await Task.WhenAny(waitTask, Task.Delay(TimeSpan.FromSeconds(timeoutSeconds)));
            if (completed != waitTask) {
                try {
                    p.Kill(entireProcessTree: true);
                } catch {
                    // Best effort kill only.
                }
                sb.AppendLine($"Failed: command timed out after {timeoutSeconds}s.");
                return (-2, sb.ToString());
            }
            return (p.ExitCode, sb.ToString());
        }

        private void AppendOutput(string text) {
            OutputTextBox.AppendText(text + Environment.NewLine);
            OutputTextBox.ScrollToEnd();
        }

        private void ShowSection(string tag) {
            HomePanel.Visibility = Visibility.Collapsed;
            BuildPanel.Visibility = Visibility.Collapsed;
            PortPanel.Visibility = Visibility.Collapsed;
            SdPanel.Visibility = Visibility.Collapsed;
            FieldPanel.Visibility = Visibility.Collapsed;
            ReadmePanel.Visibility = Visibility.Collapsed;
            GitPanel.Visibility = Visibility.Collapsed;

            switch (tag) {
                case "Build":
                    BuildPanel.Visibility = Visibility.Visible;
                    break;
                case "Port":
                    PortPanel.Visibility = Visibility.Visible;
                    break;
                case "Sd":
                    SdPanel.Visibility = Visibility.Visible;
                    break;
                case "Field":
                    FieldPanel.Visibility = Visibility.Visible;
                    break;
                case "Readme":
                    ReadmePanel.Visibility = Visibility.Visible;
                    LoadReadme();
                    LoadReadmeLogo();
                    break;
                case "Git":
                    GitPanel.Visibility = Visibility.Visible;
                    break;
                default:
                    HomePanel.Visibility = Visibility.Visible;
                    break;
            }
        }

        private void SectionButton_Click(object sender, RoutedEventArgs e) {
            if (sender is FrameworkElement el && el.Tag is string tag) {
                ShowSection(tag);
            }
        }

        private (string name, string path, int slot)? SelectedProject() {
            if (ProjectComboBox.SelectedItem is not string name) return null;
            if (!_projects.TryGetValue(name, out var data)) return null;
            return (name, System.IO.Path.Combine(RepoPath, data.path), data.slot);
        }

        private async void Build_Click(object sender, RoutedEventArgs e) {
            var p = SelectedProject();
            if (p == null) return;
            AppendOutput($"$ pros make ({p.Value.name})");
            var result = await RunCommandAsync("pros", new[] { "make" }, p.Value.path, timeoutSeconds: 600);
            AppendOutput(result.output);
        }

        private async void Upload_Click(object sender, RoutedEventArgs e) {
            var p = SelectedProject();
            if (p == null) return;
            AppendOutput($"$ pros upload --slot {p.Value.slot} ({p.Value.name})");
            var result = await RunCommandAsync("pros", new[] { "upload", "--slot", p.Value.slot.ToString(CultureInfo.InvariantCulture) }, p.Value.path, timeoutSeconds: 600);
            AppendOutput(result.output);
        }

        private async void BuildUpload_Click(object sender, RoutedEventArgs e) {
            var p = SelectedProject();
            if (p == null) return;
            AppendOutput($"$ pros make ({p.Value.name})");
            var build = await RunCommandAsync("pros", new[] { "make" }, p.Value.path, timeoutSeconds: 600);
            AppendOutput(build.output);
            if (build.code == 0) {
                AppendOutput($"$ pros upload --slot {p.Value.slot} ({p.Value.name})");
                var upload = await RunCommandAsync("pros", new[] { "upload", "--slot", p.Value.slot.ToString(CultureInfo.InvariantCulture) }, p.Value.path, timeoutSeconds: 600);
                AppendOutput(upload.output);
            }
        }

        private void UnlockRepoSettings_Click(object sender, RoutedEventArgs e) {
            var entered = RepoSettingsPasswordBox.Password.Trim();
            if (entered == RepoSettingsPassword) {
                _repoUnlocked = true;
                GitLockedPanel.Visibility = Visibility.Collapsed;
                GitUnlockedPanel.Visibility = Visibility.Visible;
                AuthErrorText.Text = "";
                RepoSettingsPasswordBox.Password = "";
                AppendOutput("Repository settings unlocked");
            } else {
                AuthErrorText.Text = "Incorrect password";
            }
        }

        private void LockRepoSettings_Click(object sender, RoutedEventArgs e) {
            _repoUnlocked = false;
            GitUnlockedPanel.Visibility = Visibility.Collapsed;
            GitLockedPanel.Visibility = Visibility.Visible;
            AuthErrorText.Text = "";
        }

        private bool EnsureUnlocked() {
            if (_repoUnlocked) return true;
            MessageBox.Show("Repository settings are locked.");
            return false;
        }

        private async void GitCommit_Click(object sender, RoutedEventArgs e) {
            if (!EnsureUnlocked()) return;
            var msg = CommitMessageTextBox.Text.Trim();
            if (msg.Length == 0) return;
            AppendOutput("$ git add -A");
            var addRes = await RunCommandAsync("git", new[] { "add", "-A" }, RepoPath, timeoutSeconds: 60, nonInteractive: true);
            AppendOutput(addRes.output);
            if (addRes.code != 0) return;
            AppendOutput("$ git commit");
            var result = await RunCommandAsync("git", new[] { "commit", "-m", msg }, RepoPath, timeoutSeconds: 90, nonInteractive: true);
            AppendOutput(result.output);
        }

        private async void GitPush_Click(object sender, RoutedEventArgs e) {
            if (!EnsureUnlocked()) return;
            AppendOutput("$ git push");
            var result = await RunCommandAsync("git", new[] { "push" }, RepoPath, timeoutSeconds: 90, nonInteractive: true);
            AppendOutput(result.output);
        }

        private async void GitTagPush_Click(object sender, RoutedEventArgs e) {
            if (!EnsureUnlocked()) return;
            var tag = TagTextBox.Text.Trim();
            if (tag.Length == 0) return;
            var msg = TagMessageTextBox.Text.Trim();
            if (msg.Length == 0) msg = tag;
            AppendOutput("$ git tag");
            var tagRes = await RunCommandAsync("git", new[] { "tag", "-a", tag, "-m", msg }, RepoPath, timeoutSeconds: 60, nonInteractive: true);
            AppendOutput(tagRes.output);
            if (tagRes.code != 0) return;
            AppendOutput("$ git push --tags");
            var pushRes = await RunCommandAsync("git", new[] { "push", "--tags" }, RepoPath, timeoutSeconds: 90, nonInteractive: true);
            AppendOutput(pushRes.output);
        }

        private async void GitRelease_Click(object sender, RoutedEventArgs e) {
            if (!EnsureUnlocked()) return;
            var tag = TagTextBox.Text.Trim();
            if (tag.Length == 0) return;
            var title = ReleaseTitleTextBox.Text.Trim();
            if (title.Length == 0) title = tag;
            var notes = ReleaseNotesTextBox.Text;
            AppendOutput("$ gh release create");
            var res = await RunCommandAsync("gh", new[] { "release", "create", tag, "--title", title, "--notes", notes }, RepoPath, timeoutSeconds: 120, nonInteractive: true);
            AppendOutput(res.output);
        }

        private void ReadmeRefresh_Click(object sender, RoutedEventArgs e) {
            LoadReadme();
            LoadReadmeLogo();
        }

        private void OpenReadmeFile_Click(object sender, RoutedEventArgs e) {
            try {
                var readmePath = Path.Combine(RepoPath, "README.md");
                if (System.IO.File.Exists(readmePath)) {
                    Process.Start(new ProcessStartInfo(readmePath) { UseShellExecute = true });
                } else {
                    MessageBox.Show($"README not found:\n{readmePath}");
                }
            } catch (Exception ex) {
                MessageBox.Show($"Failed to open README: {ex.Message}");
            }
        }

        private void LoadReadme() {
            try {
                var readmePath = Path.Combine(RepoPath, "README.md");
                ReadmeTextBox.Text = File.Exists(readmePath)
                    ? System.IO.File.ReadAllText(readmePath)
                    : $"README.md not found:\n{readmePath}";
            } catch (Exception ex) {
                ReadmeTextBox.Text = $"Failed to load README:\n{ex.Message}";
            }
        }

        private void LoadReadmeLogo() {
            var fromRepo = System.IO.Path.Combine(RepoPath, "Mac Aplications", "Tahera", "Sources", "Tahera", "Resources", "tahera_logo.png");
            var fromOutput = System.IO.Path.Combine(AppContext.BaseDirectory, "Resources", "tahera_logo.png");
            ReadmeLogoImage.Source = LoadBitmap(firstExisting(fromRepo, fromOutput));
        }

        private void LoadFieldImage() {
            var fromRepo = System.IO.Path.Combine(RepoPath, "Developer Extras", "Designs", "Feild.png");
            var fromOutput = System.IO.Path.Combine(AppContext.BaseDirectory, "Resources", "field.png");
            var bitmap = LoadBitmap(firstExisting(fromRepo, fromOutput));
            if (bitmap != null) {
                FieldImage.Source = bitmap;
            }
        }

        private void OpenReplayFile_Click(object sender, RoutedEventArgs e) {
            var dialog = new OpenFileDialog {
                Filter = "Log Files (*.txt;*.csv)|*.txt;*.csv|All Files (*.*)|*.*",
                Multiselect = false
            };
            if (dialog.ShowDialog(this) == true) {
                LoadReplayFile(dialog.FileName);
            }
        }

        private void ClearReplay_Click(object sender, RoutedEventArgs e) {
            ResetReplayState("Load a replay log (.txt or .csv) to visualize path data.");
            RedrawReplayOverlay();
        }

        private void ReplaySlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e) {
            if (_suppressReplaySliderEvent) return;
            if (_replayPoses.Count == 0) return;
            RedrawReplayOverlay();
            UpdateReplayReadout();
        }

        private void FieldOverlay_SizeChanged(object sender, SizeChangedEventArgs e) {
            RedrawReplayOverlay();
        }

        private void LoadReplayFile(string path) {
            try {
                var samples = ParseReplayLog(path);
                _replayPoses.Clear();
                _replayPoses.AddRange(IntegrateReplay(samples));

                ReplayFileText.Text = System.IO.Path.GetFileName(path);
                _suppressReplaySliderEvent = true;
                ReplaySlider.Minimum = 0;
                ReplaySlider.Maximum = Math.Max(_replayPoses.Count - 1, 0);
                ReplaySlider.Value = ReplaySlider.Maximum;
                _suppressReplaySliderEvent = false;

                RedrawReplayOverlay();
                UpdateReplayReadout();
            } catch (Exception ex) {
                ResetReplayState($"Failed to load replay file: {ex.Message}");
                RedrawReplayOverlay();
            }
        }

        private void ResetReplayState(string readout) {
            _replayPoses.Clear();
            ReplayFileText.Text = "No replay file loaded";
            _suppressReplaySliderEvent = true;
            ReplaySlider.Minimum = 0;
            ReplaySlider.Maximum = 0;
            ReplaySlider.Value = 0;
            _suppressReplaySliderEvent = false;
            ReplayReadoutText.Text = readout;
        }

        private void RedrawReplayOverlay() {
            FieldOverlay.Children.Clear();
            if (_replayPoses.Count == 0) return;
            if (FieldOverlay.ActualWidth < 2 || FieldOverlay.ActualHeight < 2) return;

            var idx = Math.Clamp((int)Math.Round(ReplaySlider.Value), 0, _replayPoses.Count - 1);
            var width = FieldOverlay.ActualWidth;
            var height = FieldOverlay.ActualHeight;

            var line = new System.Windows.Shapes.Polyline {
                Stroke = new SolidColorBrush(Color.FromRgb(76, 215, 168)),
                StrokeThickness = 2.4,
                StrokeLineJoin = PenLineJoin.Round
            };

            for (var i = 0; i <= idx; i++) {
                line.Points.Add(ToCanvasPoint(_replayPoses[i], width, height));
            }

            if (line.Points.Count > 1) {
                FieldOverlay.Children.Add(line);
            }

            var pose = _replayPoses[idx];
            var center = ToCanvasPoint(pose, width, height);
            var headingLen = Math.Max(12.0, width * 0.03);
            var heading = new Point(
                center.X + Math.Cos(pose.Theta) * headingLen,
                center.Y - Math.Sin(pose.Theta) * headingLen
            );

            var marker = new System.Windows.Shapes.Ellipse {
                Width = 10,
                Height = 10,
                Fill = new SolidColorBrush(Color.FromRgb(255, 109, 90))
            };
            Canvas.SetLeft(marker, center.X - marker.Width / 2.0);
            Canvas.SetTop(marker, center.Y - marker.Height / 2.0);
            FieldOverlay.Children.Add(marker);

            var headingLine = new System.Windows.Shapes.Line {
                X1 = center.X,
                Y1 = center.Y,
                X2 = heading.X,
                Y2 = heading.Y,
                Stroke = new SolidColorBrush(Color.FromRgb(252, 239, 199)),
                StrokeThickness = 2.0
            };
            FieldOverlay.Children.Add(headingLine);
        }

        private void UpdateReplayReadout() {
            if (_replayPoses.Count == 0) {
                ReplayReadoutText.Text = "No replay data loaded.";
                return;
            }

            var idx = Math.Clamp((int)Math.Round(ReplaySlider.Value), 0, _replayPoses.Count - 1);
            var pose = _replayPoses[idx];

            ReplayReadoutText.Text = string.Format(
                CultureInfo.InvariantCulture,
                "frame={0}/{1}  t={2:0.00}s  x={3:0.0}in  y={4:0.0}in\nleft={5:0} right={6:0}\na1={7:0} a2={8:0} a3={9:0} a4={10:0}\nlast={11}",
                idx + 1,
                _replayPoses.Count,
                pose.T,
                pose.X,
                pose.Y,
                pose.LeftCmd,
                pose.RightCmd,
                pose.Axis1,
                pose.Axis2,
                pose.Axis3,
                pose.Axis4,
                pose.Action
            );
        }

        private static string? firstExisting(params string[] candidates) {
            foreach (var candidate in candidates) {
                if (File.Exists(candidate)) return candidate;
            }
            return null;
        }

        private static BitmapImage? LoadBitmap(string? path) {
            if (string.IsNullOrWhiteSpace(path) || !System.IO.File.Exists(path)) return null;
            var image = new BitmapImage();
            image.BeginInit();
            image.CacheOption = BitmapCacheOption.OnLoad;
            image.UriSource = new Uri(path, UriKind.Absolute);
            image.EndInit();
            image.Freeze();
            return image;
        }

        private static Point ToCanvasPoint(ReplayPose pose, double width, double height) {
            var x = (pose.X / ReplayFieldSizeIn) * width;
            var y = ((ReplayFieldSizeIn - pose.Y) / ReplayFieldSizeIn) * height;
            return new Point(x, y);
        }

        private static List<ReplaySample> ParseReplayLog(string path) {
            var lines = System.IO.File.ReadAllLines(path);
            if (lines.Length == 0) return new List<ReplaySample>();
            if (lines[0].Contains("time_s", StringComparison.OrdinalIgnoreCase)) {
                return ParseReplayCsv(lines);
            }
            return ParseReplayEvents(lines);
        }

        private static List<ReplaySample> ParseReplayCsv(string[] lines) {
            var headers = lines[0].Split(',');
            var index = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            for (var i = 0; i < headers.Length; i++) {
                index[headers[i].Trim()] = i;
            }

            string get(string[] cols, string key) {
                return index.TryGetValue(key, out var idx) && idx < cols.Length ? cols[idx].Trim() : string.Empty;
            }

            var result = new List<ReplaySample>();
            for (var i = 1; i < lines.Length; i++) {
                if (string.IsNullOrWhiteSpace(lines[i])) continue;
                var cols = lines[i].Split(',');
                var t = ParseDouble(get(cols, "time_s"));
                var a1 = ParseDouble(get(cols, "axis1"));
                var a2 = ParseDouble(get(cols, "axis2"));
                var a3 = ParseDouble(get(cols, "axis3"));
                var a4 = ParseDouble(get(cols, "axis4"));
                var intake = get(cols, "intake_action");
                var outtake = get(cols, "outtake_action");
                var action = string.Empty;
                if (intake.Length > 0 || outtake.Length > 0) {
                    action = $"INTAKE:{intake} OUT:{outtake}";
                }
                result.Add(new ReplaySample(t, a1, a2, a3, a4, action));
            }
            return result;
        }

        private static List<ReplaySample> ParseReplayEvents(string[] lines) {
            var result = new List<ReplaySample>();
            double? axis1 = null;
            double? axis2 = null;
            double? axis3 = null;
            double? axis4 = null;
            var lastAction = string.Empty;
            var t = 0.0;

            foreach (var raw in lines) {
                var line = raw.Trim();
                if (line.Length == 0) continue;
                var split = line.Split(':', 2);
                if (split.Length != 2) continue;

                var type = split[0].Trim().ToUpperInvariant();
                var value = split[1].Trim();

                if (type == "AXIS1") axis1 = ParseDouble(value);
                else if (type == "AXIS2") axis2 = ParseDouble(value);
                else if (type == "AXIS3") axis3 = ParseDouble(value);
                else if (type == "AXIS4") axis4 = ParseDouble(value);
                else lastAction = $"{type} : {value}";

                if (axis1.HasValue && axis2.HasValue && axis3.HasValue && axis4.HasValue) {
                    result.Add(new ReplaySample(t, axis1.Value, axis2.Value, axis3.Value, axis4.Value, lastAction));
                    axis1 = axis2 = axis3 = axis4 = null;
                    t += ReplayDtFallback;
                }
            }

            return result;
        }

        private static List<ReplayPose> IntegrateReplay(List<ReplaySample> samples) {
            var poses = new List<ReplayPose>();
            if (samples.Count == 0) return poses;

            var x = ReplayFieldSizeIn / 2.0;
            var y = ReplayFieldSizeIn / 2.0;
            var theta = 0.0;
            double? lastT = null;

            foreach (var sample in samples) {
                var dt = 0.0;
                if (lastT.HasValue) {
                    var diff = sample.Time - lastT.Value;
                    dt = diff > 0 ? diff : ReplayDtFallback;
                }

                var leftCmd = Math.Abs(sample.Axis3) < 5 ? 0.0 : sample.Axis3;
                var rightCmd = Math.Abs(sample.Axis2) < 5 ? 0.0 : sample.Axis2;

                var vL = (leftCmd / 100.0) * ReplayMaxSpeedInPerS;
                var vR = (rightCmd / 100.0) * ReplayMaxSpeedInPerS;
                var v = (vL + vR) / 2.0;
                var omega = (vR - vL) / ReplayTrackWidthIn;

                if (dt > 0) {
                    x += v * Math.Cos(theta) * dt;
                    y += v * Math.Sin(theta) * dt;
                    theta += omega * dt;
                }

                poses.Add(new ReplayPose(
                    sample.Time,
                    x,
                    y,
                    theta,
                    leftCmd,
                    rightCmd,
                    sample.Axis1,
                    sample.Axis2,
                    sample.Axis3,
                    sample.Axis4,
                    sample.Action
                ));

                lastT = sample.Time;
            }

            return poses;
        }

        private static double ParseDouble(string value) {
            if (double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out var parsed)) {
                return parsed;
            }
            return 0.0;
        }

        private sealed record ReplaySample(double Time, double Axis1, double Axis2, double Axis3, double Axis4, string Action);

        private sealed record ReplayPose(
            double T,
            double X,
            double Y,
            double Theta,
            double LeftCmd,
            double RightCmd,
            double Axis1,
            double Axis2,
            double Axis3,
            double Axis4,
            string Action
        );
    }
}
