using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading;
using System.Web.Script.Serialization;

namespace SynSeeder
{
    /// <summary>Starting, finding and closing the game.</summary>
    sealed class Game
    {
        // HLL Vietnam's game process in the Steam and the Epic build.
        static readonly string[] Processes = { "HLLVietnam-Win64-Shipping", "HLLVietnamEpicGamesStore-Win64-Shipping" };
        const string EpicAppName = "d7361b7d6fa94097bcadeac4b1f785fb";

        readonly Config config;

        public Game(Config config) => this.config = config;

        public string LaunchUri()
        {
            if (config.Launcher != "epic")
                return "steam://rungameid/" + config.SteamAppId;
            string app = string.IsNullOrWhiteSpace(config.EpicAppName) ? DetectEpicApp() : config.EpicAppName.Trim();
            if (app.Length == 0)
                throw new InvalidOperationException("Couldn't find HLL Vietnam in the Epic Games launcher");
            return "com.epicgames.launcher://apps/" + Uri.EscapeDataString(Uri.UnescapeDataString(app)) + "?action=launch&silent=true";
        }

        /// <summary>Asks Steam or Epic to start the game, then waits for its process.</summary>
        public bool Launch(CancellationToken stop)
        {
            string uri = LaunchUri();
            Log.Write("Starting the game via " + uri);
            Process.Start(new ProcessStartInfo(uri) { UseShellExecute = true })?.Dispose();
            var deadline = DateTime.UtcNow.AddSeconds(config.LaunchTimeout);
            while (DateTime.UtcNow < deadline)
            {
                if (Find() != null)
                    return true;
                stop.WaitHandle.WaitOne(2000);
                stop.ThrowIfCancellationRequested();
            }
            return false;
        }

        public Process Find()
        {
            string wanted = Path.GetFileNameWithoutExtension(config.ProcessName ?? "");
            bool either = wanted.Length == 0 || Processes.Contains(wanted, StringComparer.OrdinalIgnoreCase);
            foreach (var process in Process.GetProcesses())
            {
                if (either ? Processes.Contains(process.ProcessName, StringComparer.OrdinalIgnoreCase)
                           : string.Equals(process.ProcessName, wanted, StringComparison.OrdinalIgnoreCase))
                    return process;
                process.Dispose();
            }
            return null;
        }

        public IntPtr Window()
        {
            using (var process = Find())
                return process == null ? IntPtr.Zero : Native.MainWindow(process.Id);
        }

        /// <summary>Where the game draws on screen, or the primary screen while it has no window.</summary>
        public Rectangle Area()
        {
            IntPtr hwnd = Window();
            var area = hwnd == IntPtr.Zero ? Rectangle.Empty : Native.ClientArea(hwnd);
            return area.Width > 0 && area.Height > 0 ? area : System.Windows.Forms.Screen.PrimaryScreen.Bounds;
        }

        /// <summary>Closes the game, politely first.</summary>
        public void Close()
        {
            using (var process = Find())
            {
                if (process == null)
                    return;
                Log.Write("Closing the game");
                process.CloseMainWindow();
                if (!process.WaitForExit(30000))
                    process.Kill();
            }
        }

        /// <summary>HLL Vietnam in the Epic launcher's install list, as namespace:item:app, or "".</summary>
        public static string DetectEpicApp()
        {
            string manifest = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
                                           @"Epic\UnrealEngineLauncher\LauncherInstalled.dat");
            try
            {
                var data = new JavaScriptSerializer().DeserializeObject(File.ReadAllText(manifest)) as Dictionary<string, object>;
                if (data == null || !(data.TryGetValue("InstallationList", out object list) && list is object[] installs))
                    return "";
                var entries = installs.OfType<Dictionary<string, object>>().ToList();
                string Field(Dictionary<string, object> entry, string key) => entry.TryGetValue(key, out object v) ? Convert.ToString(v) : "";
                bool ByName(Dictionary<string, object> e) => Field(e, "AppName") == EpicAppName;
                bool ByFolder(Dictionary<string, object> e)
                {
                    string folder = Regex.Replace(Field(e, "InstallLocation").ToLowerInvariant(), "[^a-z0-9]", "");
                    return folder.Contains("hellletloose") && folder.Contains("vietnam");
                }
                foreach (Func<Dictionary<string, object>, bool> match in new Func<Dictionary<string, object>, bool>[] { ByName, ByFolder })
                    foreach (var entry in entries.Where(e => Field(e, "AppName").Length > 0 && match(e)))
                    {
                        string[] ids = { Field(entry, "NamespaceId"), Field(entry, "ItemId"), Field(entry, "AppName") };
                        return ids.All(id => id.Length > 0) ? string.Join(":", ids) : ids[2];
                    }
            }
            catch (Exception error) when (error is IOException || error is ArgumentException || error is InvalidOperationException
                                          || error is UnauthorizedAccessException)
            {
            }
            return "";
        }
    }
}
