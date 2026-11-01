using System;
using System.Drawing;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace SynSeeder
{
    /// <summary>The SynSeeder window: the server's player count, the daily start, and Seed now.</summary>
    sealed class MainForm : Form
    {
        const int StopHotkey = 1;
        readonly Config config;
        readonly bool seedOnOpen;
        readonly Label players = new Label { AutoSize = true, Font = new Font("Segoe UI", 14, FontStyle.Bold) };
        readonly Label status = new Label { AutoSize = true, MaximumSize = new Size(380, 0) };
        readonly DateTimePicker startTime = new DateTimePicker { Format = DateTimePickerFormat.Custom, CustomFormat = "HH:mm", ShowUpDown = true, Width = 90 };
        readonly NumericUpDown target = new NumericUpDown { Minimum = 1, Maximum = 100, Width = 70 };
        readonly ComboBox launcher = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 140 };
        readonly CheckBox daily = new CheckBox { Text = "Start every day at this time", AutoSize = true };
        readonly Button seedNow = new Button { Text = "Seed now", AutoSize = true };
        readonly Button updates = new Button { Text = "Check for updates", AutoSize = true };
        readonly System.Windows.Forms.Timer refresh = new System.Windows.Forms.Timer { Interval = 60_000 };
        CancellationTokenSource run;

        public MainForm(Config config, bool seedOnOpen)
        {
            this.config = config;
            this.seedOnOpen = seedOnOpen;
            Text = "SynSeeder " + Program.Version;
            Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
            Font = new Font("Segoe UI", 10);
            AutoScaleMode = AutoScaleMode.Dpi;
            FormBorderStyle = FormBorderStyle.FixedSingle;
            MaximizeBox = false;
            AutoSize = true;
            AutoSizeMode = AutoSizeMode.GrowAndShrink;
            Padding = new Padding(16);

            var layout = new TableLayoutPanel { ColumnCount = 2, AutoSize = true, Dock = DockStyle.Fill };
            layout.Controls.Add(new Label { Text = config.ServerName, AutoSize = true, Font = new Font("Segoe UI", 11) }, 0, 0);
            layout.SetColumnSpan(layout.GetControlFromPosition(0, 0), 2);
            layout.Controls.Add(players, 0, 1);
            layout.SetColumnSpan(players, 2);
            layout.Controls.Add(new Label { Text = "Start time", AutoSize = true, Anchor = AnchorStyles.Left }, 0, 2);
            layout.Controls.Add(startTime, 1, 2);
            layout.Controls.Add(new Label { Text = "Seeded at (players)", AutoSize = true, Anchor = AnchorStyles.Left }, 0, 3);
            layout.Controls.Add(target, 1, 3);
            layout.Controls.Add(new Label { Text = "Game launcher", AutoSize = true, Anchor = AnchorStyles.Left }, 0, 4);
            layout.Controls.Add(launcher, 1, 4);
            layout.Controls.Add(daily, 0, 5);
            layout.SetColumnSpan(daily, 2);
            var buttons = new FlowLayoutPanel { AutoSize = true };
            buttons.Controls.Add(seedNow);
            buttons.Controls.Add(updates);
            layout.Controls.Add(buttons, 0, 6);
            layout.SetColumnSpan(buttons, 2);
            layout.Controls.Add(status, 0, 7);
            layout.SetColumnSpan(status, 2);
            Controls.Add(layout);

            launcher.Items.AddRange(new object[] { "Steam", "Epic Games" });
            launcher.SelectedIndex = config.Launcher == "epic" ? 1 : 0;
            target.Value = Math.Max(1, Math.Min(100, config.SeededThreshold));
            startTime.Value = DateTime.Today.Add(TimeSpan.TryParse(config.StartTime, out var at) ? at : TimeSpan.FromHours(7));
            daily.Checked = TaskSchedule.IsScheduled();

            seedNow.Click += (s, e) => ToggleRun();
            updates.Click += async (s, e) => await CheckForUpdatesAsync();
            daily.CheckedChanged += (s, e) => SaveSchedule();
            startTime.ValueChanged += (s, e) => { if (daily.Checked) SaveSchedule(); };
            target.ValueChanged += (s, e) => SaveSettings();
            launcher.SelectedIndexChanged += (s, e) => SaveSettings();
            refresh.Tick += async (s, e) => await RefreshPlayersAsync();
            Shown += async (s, e) =>
            {
                refresh.Start();
                await RefreshPlayersAsync();
                if (this.seedOnOpen)
                    ToggleRun();
            };
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            Native.RegisterHotKey(Handle, StopHotkey, Native.MOD_CONTROL | Native.MOD_ALT | Native.MOD_NOREPEAT, Native.VK_END);
        }

        protected override void OnHandleDestroyed(EventArgs e)
        {
            Native.UnregisterHotKey(Handle, StopHotkey);
            base.OnHandleDestroyed(e);
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == Native.WM_HOTKEY && m.WParam.ToInt32() == StopHotkey)
                run?.Cancel();  // Ctrl+Alt+End stops a run from anywhere, even in game
            base.WndProc(ref m);
        }

        async Task RefreshPlayersAsync()
        {
            var server = await Stats.FetchAsync(config.CrconUrl);
            players.Text = server == null ? "Players: unknown" : $"Players: {server.Players} / {config.SeededThreshold}";
        }

        void SaveSettings()
        {
            config.SeededThreshold = (int)target.Value;
            config.Launcher = launcher.SelectedIndex == 1 ? "epic" : "steam";
            config.StartTime = startTime.Value.ToString("HH:mm");
            config.Save();
        }

        void SaveSchedule()
        {
            SaveSettings();
            try
            {
                if (daily.Checked)
                    TaskSchedule.Schedule(config.StartTime, TaskSchedule.InstalledCopy());
                else
                    TaskSchedule.Unschedule();
                status.Text = daily.Checked ? "SynSeeder will start every day at " + config.StartTime + "." : "Daily start turned off.";
            }
            catch (Exception error) when (error is System.Runtime.InteropServices.COMException || error is UnauthorizedAccessException
                                          || error is System.IO.IOException)
            {
                status.Text = "Couldn't change the daily start: " + error.Message;
            }
        }

        void ToggleRun()
        {
            if (run != null)
            {
                run.Cancel();
                return;
            }
            run = new CancellationTokenSource();
            var token = run.Token;
            seedNow.Text = "Stop";
            void Report(string text) => BeginInvoke((Action)(() => status.Text = text));
            Task.Run(async () =>
            {
#if SELF_UPDATE
                if (await Updater.UpdateAndHandOverAsync(config, seedOnOpen ? new[] { "--seed" } : new string[0]))
                {
                    BeginInvoke((Action)Close);
                    return;
                }
#else
                await Task.CompletedTask;
#endif
                var vision = new Vision(Vision.LoadTemplates());
                new Seeder(config, vision, token, Report).Run();
            }, token).ContinueWith(task =>
            {
                if (task.IsFaulted)
                    Log.Write("The run stopped with an error: " + task.Exception?.GetBaseException());
                BeginInvoke((Action)(() =>
                {
                    run = null;
                    seedNow.Text = "Seed now";
                    if (task.IsCanceled)
                        status.Text = "Stopped.";
                    if (seedOnOpen)
                        Close();
                }));
            });
        }

        async Task CheckForUpdatesAsync()
        {
            updates.Enabled = false;
            var release = await Updater.LatestAsync();
            updates.Enabled = true;
            if (release == null || release.Version <= Updater.Current)
            {
                status.Text = "You have the latest version.";
                return;
            }
#if SELF_UPDATE
            status.Text = release.Tag + " is out. It installs itself before the next run.";
#else
            status.Text = release.Tag + " is out. Download it from the page that just opened.";
            Updater.OpenPage(release);
#endif
        }
    }
}
