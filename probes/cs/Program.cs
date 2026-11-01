using System;
using System.Linq;
using System.Threading;
using System.Windows.Forms;

namespace SynSeeder
{
    static class Program
    {
        public const string Version = "0.9.0";

        [STAThread]
        static int Main(string[] args)
        {
            if (args.Contains("--selftest"))
                return SelfTest.Run(args);
#if SELF_UPDATE
            int at = Array.IndexOf(args, "--install-to");
            if (at >= 0 && at + 1 < args.Length)
                Updater.Install(args[at + 1], OldPids(args));
#endif
            bool seed = args.Contains("--seed");
            using (var window = new Mutex(false, seed ? @"Local\SynSeederSeeding" : @"Local\SynSeederWindow", out bool first))
            {
                if (!first)
                    return 0;  // already open, or a seeding run is already going
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new MainForm(Config.Load(), seed));
            }
            return 0;
        }

#if SELF_UPDATE
        static int[] OldPids(string[] args)
        {
            return args.Select((arg, i) => arg == "--old-pid" && i + 1 < args.Length && int.TryParse(args[i + 1], out int pid) ? pid : -1)
                       .Where(pid => pid > 0).ToArray();
        }
#endif
    }
}
