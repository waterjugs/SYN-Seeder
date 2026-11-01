using System;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Security;

namespace SynSeeder
{
    /// <summary>
    /// The daily start, as a Windows scheduled task in the user's own account (never as administrator).
    /// It's registered from XML so it can also run on battery, start late if the PC was off at the time,
    /// and never start twice.
    /// </summary>
    static class TaskSchedule
    {
        const string Name = "SynSeeder";
        const int CreateOrUpdate = 6, InteractiveToken = 3;

        static dynamic Folder()
        {
            dynamic service = Activator.CreateInstance(Type.GetTypeFromProgID("Schedule.Service", true));
            service.Connect();
            return service.GetFolder("\\");
        }

        public static void Schedule(string startTime, string program)
        {
            Folder().RegisterTask(Name, Xml(startTime, program, "--seed", DateTime.Now), CreateOrUpdate, null, null, InteractiveToken, null);
            Log.Write("Scheduled a daily start at " + startTime);
        }

        public static void Unschedule()
        {
            if (IsScheduled())
                Folder().DeleteTask(Name, 0);
        }

        public static bool IsScheduled()
        {
            try
            {
                Folder().GetTask(Name);
                return true;
            }
            catch (COMException)
            {
                return false;
            }
            catch (FileNotFoundException)
            {
                return false;
            }
        }

        /// <summary>
        /// Where the task starts SynSeeder from: a copy in %LOCALAPPDATA%\SynSeeder, so the task keeps working
        /// if the download is moved or deleted.
        /// </summary>
        public static string InstalledCopy()
        {
            string folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SynSeeder");
            string target = Path.Combine(folder, "SynSeeder.exe");
            string current = System.Windows.Forms.Application.ExecutablePath;
            if (!string.Equals(Path.GetFullPath(current), Path.GetFullPath(target), StringComparison.OrdinalIgnoreCase) && !NewerInstalled(target))
            {
                Directory.CreateDirectory(folder);
                File.Copy(current, target, true);
            }
            return target;
        }

        static bool NewerInstalled(string target)
        {
            if (!File.Exists(target))
                return false;
            var installed = System.Diagnostics.FileVersionInfo.GetVersionInfo(target);
            return Version.TryParse(installed.FileVersion, out var version) && version > Version.Parse(Program.Version);
        }

        public static string Xml(string startTime, string program, string arguments, DateTime now)
        {
            var parts = startTime.Split(':');
            var start = now.Date.AddHours(int.Parse(parts[0])).AddMinutes(int.Parse(parts[1]));
            if (start <= now)
                start = start.AddDays(1);
            string user = (Environment.UserDomainName + "\\" + Environment.UserName).Trim('\\');
            return "<?xml version=\"1.0\" encoding=\"UTF-16\"?>\n"
                + "<Task version=\"1.2\" xmlns=\"http://schemas.microsoft.com/windows/2004/02/mit/task\">\n"
                + "  <RegistrationInfo>\n"
                + "    <Description>Seeds the Syndicate HLL Vietnam server. Change it from SynSeeder.exe.</Description>\n"
                + "  </RegistrationInfo>\n"
                + "  <Triggers>\n"
                + "    <CalendarTrigger>\n"
                + "      <StartBoundary>" + start.ToString("yyyy-MM-dd'T'HH:mm:ss", CultureInfo.InvariantCulture) + "</StartBoundary>\n"
                + "      <Enabled>true</Enabled>\n"
                + "      <ScheduleByDay>\n"
                + "        <DaysInterval>1</DaysInterval>\n"
                + "      </ScheduleByDay>\n"
                + "    </CalendarTrigger>\n"
                + "  </Triggers>\n"
                + "  <Principals>\n"
                + "    <Principal id=\"Author\">\n"
                + "      <UserId>" + SecurityElement.Escape(user) + "</UserId>\n"
                + "      <LogonType>InteractiveToken</LogonType>\n"
                + "      <RunLevel>LeastPrivilege</RunLevel>\n"
                + "    </Principal>\n"
                + "  </Principals>\n"
                + "  <Settings>\n"
                + "    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>\n"
                + "    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>\n"
                + "    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>\n"
                + "    <StartWhenAvailable>true</StartWhenAvailable>\n"
                + "    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>\n"
                + "    <IdleSettings>\n"
                + "      <StopOnIdleEnd>false</StopOnIdleEnd>\n"
                + "      <RestartOnIdle>false</RestartOnIdle>\n"
                + "    </IdleSettings>\n"
                + "    <Enabled>true</Enabled>\n"
                + "    <ExecutionTimeLimit>PT6H</ExecutionTimeLimit>\n"
                + "    <Priority>7</Priority>\n"
                + "  </Settings>\n"
                + "  <Actions Context=\"Author\">\n"
                + "    <Exec>\n"
                + "      <Command>" + SecurityElement.Escape(program) + "</Command>\n"
                + "      <Arguments>" + SecurityElement.Escape(arguments) + "</Arguments>\n"
                + "    </Exec>\n"
                + "  </Actions>\n"
                + "</Task>\n";
        }
    }
}
