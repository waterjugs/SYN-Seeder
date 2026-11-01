using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Security.Cryptography;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace SynSeeder
{
    sealed class Release
    {
        public string Tag;
        public Version Version;
        public string Page;
        public string ExeUrl;
        public string Sha256;  // from GitHub's asset digest, when it gives one
    }

    /// <summary>Finding out whether a newer SynSeeder is out on GitHub.</summary>
    static class Updater
    {
        const string LatestRelease = "https://api.github.com/repos/waterjugs/SYN-Seeder/releases/latest";
        public const string ReleasesPage = "https://github.com/waterjugs/SYN-Seeder/releases/latest";

        public static Version Current => Version.Parse(Program.Version);

        /// <summary>The latest published release, or null when there's none or GitHub can't be reached.</summary>
        public static async Task<Release> LatestAsync()
        {
            try
            {
                var payload = await Net.GetJsonAsync(LatestRelease, "application/vnd.github+json").ConfigureAwait(false);
                return Parse(payload);
            }
            catch (Exception error) when (error is HttpRequestException || error is TaskCanceledException
                                          || error is ArgumentException || error is InvalidOperationException)
            {
                Log.Write("Couldn't check for updates: " + error.Message);
                return null;
            }
        }

        public static Release Parse(Dictionary<string, object> payload)
        {
            if (payload == null || !(payload.TryGetValue("tag_name", out object tag) && tag is string name)
                || !Version.TryParse(name.TrimStart('v'), out var version))
                return null;
            var release = new Release
            {
                Tag = name,
                Version = version,
                Page = payload.TryGetValue("html_url", out object page) ? Convert.ToString(page) : ReleasesPage,
            };
            if (payload.TryGetValue("assets", out object list) && list is object[] assets)
                foreach (var asset in assets.OfType<Dictionary<string, object>>())
                    if (asset.TryGetValue("name", out object file) && Convert.ToString(file) == "SynSeeder.exe"
                        && asset.TryGetValue("browser_download_url", out object url) && Convert.ToString(url).StartsWith("https://"))
                    {
                        release.ExeUrl = Convert.ToString(url);
                        if (asset.TryGetValue("digest", out object digest) && Convert.ToString(digest).StartsWith("sha256:"))
                            release.Sha256 = Convert.ToString(digest).Substring(7);
                    }
            return release;
        }

#if SELF_UPDATE
        static string Folder => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SynSeeder");

        /// <summary>
        /// Before a run: if a newer release is out, downloads it and lets it take over. True means the new
        /// version has the run and this process should exit.
        /// </summary>
        public static async Task<bool> UpdateAndHandOverAsync(Config config, string[] args)
        {
            if (!config.AutoUpdate)
                return false;
            var release = await LatestAsync().ConfigureAwait(false);
            if (release == null || release.ExeUrl == null || release.Version <= Current)
                return false;
            Log.Write("Updating from v" + Program.Version + " to " + release.Tag);
            Directory.CreateDirectory(Folder);
            string fresh = Path.Combine(Folder, "SynSeeder-update.exe");
            if (!await DownloadAsync(release, fresh).ConfigureAwait(false))
                return false;
            var start = new ProcessStartInfo(fresh)
            {
                UseShellExecute = false,
                Arguments = "--install-to \"" + Application.ExecutablePath + "\" --old-pid " + Process.GetCurrentProcess().Id
                            + (args.Contains("--seed") ? " --seed" : ""),
            };
            using (Process.Start(start))
                return true;
        }

        static async Task<bool> DownloadAsync(Release release, string path)
        {
            string part = path + ".part";
            try
            {
                using (var response = await Net.Client.GetAsync(release.ExeUrl, HttpCompletionOption.ResponseHeadersRead).ConfigureAwait(false))
                {
                    response.EnsureSuccessStatusCode();
                    using (var file = File.Create(part))
                        await response.Content.CopyToAsync(file).ConfigureAwait(false);
                }
                if (release.Sha256 != null && !string.Equals(Sha256(part), release.Sha256, StringComparison.OrdinalIgnoreCase))
                {
                    Log.Write("The download doesn't match the release's SHA-256, so it wasn't used");
                    File.Delete(part);
                    return false;
                }
                if (File.Exists(path))
                    File.Delete(path);
                File.Move(part, path);
                return true;
            }
            catch (Exception error) when (error is HttpRequestException || error is IOException || error is TaskCanceledException
                                          || error is UnauthorizedAccessException)
            {
                Log.Write("Couldn't download " + release.Tag + ": " + error.Message);
                return false;
            }
        }

        static string Sha256(string path)
        {
            using (var sha = SHA256.Create())
            using (var stream = File.OpenRead(path))
                return string.Concat(sha.ComputeHash(stream).Select(b => b.ToString("x2")));
        }

        /// <summary>Run by the new version: waits for the old one to close, then copies itself over it.</summary>
        public static void Install(string target, int[] oldPids)
        {
            foreach (int pid in oldPids)
                try
                {
                    using (var old = Process.GetProcessById(pid))
                        old.WaitForExit(60000);
                }
                catch (ArgumentException)
                {
                    // already gone
                }
            string temp = target + ".new";
            for (int attempt = 0; attempt < 30; attempt++)
                try
                {
                    File.Copy(Application.ExecutablePath, temp, true);
                    if (File.Exists(target))
                        File.Replace(temp, target, null);
                    else
                        File.Move(temp, target);
                    Log.Write("Installed v" + Program.Version);
                    return;
                }
                catch (IOException)
                {
                    Thread.Sleep(2000);
                }
                catch (UnauthorizedAccessException)
                {
                    Thread.Sleep(2000);
                }
            Log.Write("Couldn't replace " + target + "; the next run will try again");
        }
#endif

        /// <summary>Opens the release page in the browser.</summary>
        public static void OpenPage(Release release) =>
            Process.Start(new ProcessStartInfo(release?.Page ?? ReleasesPage) { UseShellExecute = true })?.Dispose();
    }
}
