using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Web.Script.Serialization;

namespace SynSeeder
{
    /// <summary>Settings, kept as JSON in %APPDATA%\SynSeeder\config.json (same keys as the Python version).</summary>
    sealed class Config
    {
        public string ServerName = "Syndicate | Competitive Server";
        public string ServerSearch = "syndicate";
        public string CrconUrl = "https://syn-stats-nam.radicalgamingstats.com/api/get_public_info";
        public int SeededThreshold = 80;
        public int LeaveDelayMinutes = 10;
        public string Launcher = "steam";
        public int SteamAppId = 3079210;
        public string EpicAppName = "";
        public string ProcessName = "HLLVietnam-Win64-Shipping.exe";
        public string StartTime = "07:00";
        public bool AutoUpdate = true;
        public int PollSeconds = 30;
        public int LaunchTimeout = 300;
        public int MaxMinutes = 240;

        public static string Folder
        {
            get
            {
                string path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "SynSeeder");
                Directory.CreateDirectory(path);
                return path;
            }
        }

        static string FilePath => Path.Combine(Folder, "config.json");

        public static Config Load()
        {
            var config = new Config();
            try
            {
                if (!File.Exists(FilePath))
                    return config;
                if (!(new JavaScriptSerializer().DeserializeObject(File.ReadAllText(FilePath, Encoding.UTF8)) is Dictionary<string, object> data))
                    return config;
                config.ServerName = Text(data, "server_name", config.ServerName);
                config.ServerSearch = Text(data, "server_search", config.ServerSearch);
                config.CrconUrl = Text(data, "crcon_url", config.CrconUrl);
                config.SeededThreshold = Number(data, "seeded_threshold", config.SeededThreshold);
                config.LeaveDelayMinutes = Number(data, "leave_delay_minutes", config.LeaveDelayMinutes);
                config.Launcher = Text(data, "launcher", config.Launcher);
                config.SteamAppId = Number(data, "steam_app_id", config.SteamAppId);
                config.EpicAppName = Text(data, "epic_app_name", config.EpicAppName);
                config.ProcessName = Text(data, "process_name", config.ProcessName);
                config.StartTime = Text(data, "start_time", config.StartTime);
                config.AutoUpdate = data.TryGetValue("auto_update", out object update) && update is bool on ? on : config.AutoUpdate;
                config.PollSeconds = Number(data, "poll_seconds", config.PollSeconds);
                config.LaunchTimeout = Number(data, "launch_timeout", config.LaunchTimeout);
                config.MaxMinutes = Number(data, "max_minutes", config.MaxMinutes);
            }
            catch (Exception error) when (error is IOException || error is ArgumentException || error is InvalidOperationException)
            {
                Log.Write("Couldn't read the settings, using the defaults: " + error.Message);
            }
            return config;
        }

        public void Save()
        {
            var data = new Dictionary<string, object>
            {
                ["server_name"] = ServerName,
                ["server_search"] = ServerSearch,
                ["crcon_url"] = CrconUrl,
                ["seeded_threshold"] = SeededThreshold,
                ["leave_delay_minutes"] = LeaveDelayMinutes,
                ["launcher"] = Launcher,
                ["steam_app_id"] = SteamAppId,
                ["epic_app_name"] = EpicAppName,
                ["process_name"] = ProcessName,
                ["start_time"] = StartTime,
                ["auto_update"] = AutoUpdate,
                ["poll_seconds"] = PollSeconds,
                ["launch_timeout"] = LaunchTimeout,
                ["max_minutes"] = MaxMinutes,
            };
            File.WriteAllText(FilePath, new JavaScriptSerializer().Serialize(data), new UTF8Encoding(false));
        }

        static string Text(Dictionary<string, object> data, string key, string fallback)
        {
            return data.TryGetValue(key, out object value) && value is string text ? text : fallback;
        }

        static int Number(Dictionary<string, object> data, string key, int fallback)
        {
            return data.TryGetValue(key, out object value) && value is int number ? number : fallback;
        }
    }

    /// <summary>A plain text log next to the settings, like the Python version's seeder.log.</summary>
    static class Log
    {
        static readonly object Gate = new object();

        public static void Write(string message)
        {
            try
            {
                lock (Gate)
                    File.AppendAllText(Path.Combine(Config.Folder, "seeder.log"),
                        DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " " + message + Environment.NewLine);
            }
            catch (IOException)
            {
                // A log that can't be written mustn't stop a run.
            }
        }
    }
}
