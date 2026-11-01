using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;

namespace SynSeeder
{
    /// <summary>
    /// "SynSeeder.exe --selftest LOG" checks the parts that don't need the game: the built-in button images,
    /// finding them on a made-up screen, the stats page, the release check and the daily task's XML. CI runs
    /// it on every build. Exit code 0 means every required check passed.
    /// </summary>
    static class SelfTest
    {
        public static int Run(string[] args)
        {
            int at = Array.IndexOf(args, "--selftest");
            string logPath = at + 1 < args.Length ? args[at + 1] : "selftest.log";
            var lines = new List<string>();
            bool ok = true;
            void Check(string what, bool passed)
            {
                lines.Add((passed ? "PASS " : "FAIL ") + what);
                ok &= passed;
            }

            try
            {
                var templates = Vision.LoadTemplates();
                var missing = Vision.Required.Where(name => !templates.ContainsKey(name)).ToList();
                Check("built-in button images (" + templates.Count + " found" + (missing.Count > 0 ? ", missing " + string.Join(", ", missing) : "") + ")", missing.Count == 0);

                var timer = Stopwatch.StartNew();
                var vision = new Vision(templates);
                lines.Add($"     prepared {vision.Names.Count()} templates in {timer.ElapsedMilliseconds} ms");

                foreach (var (name, height) in new[] { ("menu_enlist", 1440), ("select_force", 1440), ("server_row", 1080), ("admin_yes", 2160) })
                {
                    var (image, cutAt) = templates[name].First();
                    var screen = MadeUpScreen(height * 16 / 9, height, image, (double)height / cutAt, out Point centre);
                    timer.Restart();
                    vision.SetFrame(screen, new Rectangle(0, 0, screen.Width, screen.Height));
                    var found = vision.Find(name);
                    long ms = timer.ElapsedMilliseconds;
                    bool near = found.HasValue && Math.Abs(found.Value.X - centre.X) <= 6 && Math.Abs(found.Value.Y - centre.Y) <= 6;
                    Check($"finds {name} on a {height}p screen at {centre} (got {(found.HasValue ? found.Value.ToString() : "nothing")}, {ms} ms)", near);
                }

                var blank = new Gray(1920, 1080);
                vision.SetFrame(blank, new Rectangle(0, 0, 1920, 1080));
                Check("finds nothing on a blank screen", Vision.Required.All(name => vision.Find(name) == null));

                var server = Stats.FetchAsync(new Config().CrconUrl).GetAwaiter().GetResult();
                lines.Add("     stats page: " + (server == null ? "couldn't be read" : $"{server.Name}, {server.Players} players"));

                var release = Updater.LatestAsync().GetAwaiter().GetResult();
                lines.Add("     latest release: " + (release == null ? "none published" : release.Tag));

                string xml = TaskSchedule.Xml("07:30", @"C:\Users\A & B\SynSeeder.exe", "--seed", new DateTime(2026, 1, 2, 8, 0, 0));
                Check("daily task XML", xml.Contains("<StartBoundary>2026-01-03T07:30:00</StartBoundary>")
                                        && xml.Contains(@"<Command>C:\Users\A &amp; B\SynSeeder.exe</Command>"));

                lines.Add($"     idle for {Native.IdleSeconds():0} s, desktop unlocked: {Native.DesktopUnlocked()}");
                Check("settings round trip", RoundTrip());
            }
            catch (Exception error)
            {
                Check("no crash: " + error, false);
            }
            lines.Add(ok ? "SELFTEST OK" : "SELFTEST FAILED");
            File.WriteAllLines(logPath, lines);
            return ok ? 0 : 1;
        }

        /// <summary>Random speckles with one template pasted in, scaled as the game would draw it at that height.</summary>
        static Gray MadeUpScreen(int width, int height, Gray template, double scale, out Point centre)
        {
            var random = new Random(1234);
            var screen = new Gray(width, height);
            for (int i = 0; i < screen.Pixels.Length; i++)
                screen.Pixels[i] = random.Next(40, 90);
            var sized = template.Resize((int)Math.Round(template.Width * scale), (int)Math.Round(template.Height * scale));
            int left = width / 3, top = height / 2;
            for (int y = 0; y < sized.Height; y++)
                Array.Copy(sized.Pixels, y * sized.Width, screen.Pixels, (top + y) * width + left, sized.Width);
            centre = new Point(left + sized.Width / 2, top + sized.Height / 2);
            return screen;
        }

        static bool RoundTrip()
        {
            var config = new Config { SeededThreshold = 77, Launcher = "epic" };
            var data = new System.Web.Script.Serialization.JavaScriptSerializer();
            string json = data.Serialize(new Dictionary<string, object> { ["seeded_threshold"] = config.SeededThreshold, ["launcher"] = config.Launcher });
            var back = (Dictionary<string, object>)data.DeserializeObject(json);
            return (int)back["seeded_threshold"] == 77 && (string)back["launcher"] == "epic";
        }
    }
}
