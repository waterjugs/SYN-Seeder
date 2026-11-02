; The daily Windows scheduled task, and keeping one stable copy of the exe.
;
; The task is registered from XML so it can also run on battery, start late if
; the PC was off or asleep at the time, and never start twice. It runs in the
; player's own account, never as administrator.

class DailyTask {
    static NAME := "SynSeeder"

    ; [program, arguments] that start a seeding run.
    ;
    ; A built exe copies itself to %LOCALAPPDATA%\SynSeeder first, so the task
    ; keeps working if the download is moved or deleted. It leaves a newer
    ; copy there alone: that one has updated itself since this exe was downloaded.
    static SeedCommand() {
        if !A_IsCompiled
            return [A_AhkPath, QuoteArg(A_ScriptFullPath) " --seed"]
        target := App.InstallDir "\" App.NAME ".exe"
        if !SamePath(A_ScriptFullPath, target) && !DailyTask.NewerInstalled(target)
            && Sha256.File(target) != Sha256.File(A_ScriptFullPath) {
            DirCreate(App.InstallDir)
            try {
                FileCopy(A_ScriptFullPath, target, true)
            } catch as err {
                throw Error("Couldn't copy SynSeeder.exe to " App.InstallDir " (" err.Message "). "
                    . "If a run is going, stop it and try again.")
            }
        }
        return [target, "--seed"]
    }

    ; True if the exe at ``target`` is a newer SynSeeder than this one.
    static NewerInstalled(target) {
        if !FileExist(target)
            return false
        try
            installed := App.ParseVersion(RegExReplace(FileGetVersion(target), "\.\d+$"))
        catch
            return false
        return installed != "" && App.CompareVersions(installed, App.ParseVersion(App.VERSION)) > 0
    }

    ; The task's XML. Starts at ``startTime`` (24-hour "HH:MM", local time)
    ; every day from the next time it comes round.
    static Xml(startTime, program, arguments, now := "") {
        now := now != "" ? now : A_Now
        parts := StrSplit(startTime, ":")
        start := SubStr(now, 1, 8) Format("{:02d}{:02d}00", Integer(parts[1]), Integer(parts[2]))
        if DateDiff(start, now, "Seconds") <= 0
            start := DateAdd(start, 1, "Days")
        user := EnvGet("USERDOMAIN") "\" EnvGet("USERNAME")
        user := Trim(user, "\")
        return Format('
        (
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Seeds the Syndicate HLL Vietnam server. Change it from SynSeeder.exe.</Description>
  </RegistrationInfo>
  <Triggers>
    <CalendarTrigger>
      <StartBoundary>{1}</StartBoundary>
      <Enabled>true</Enabled>
      <ScheduleByDay>
        <DaysInterval>1</DaysInterval>
      </ScheduleByDay>
    </CalendarTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>{2}</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <Enabled>true</Enabled>
    <ExecutionTimeLimit>PT6H</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>{3}</Command>
      <Arguments>{4}</Arguments>
    </Exec>
  </Actions>
</Task>

        )', FormatTime(start, "yyyy-MM-dd'T'HH:mm:ss"), XmlEscape(user), XmlEscape(program), XmlEscape(arguments))
    }

    static _Folder() {
        service := ComObject("Schedule.Service")
        service.Connect()
        return service.GetFolder("\")
    }

    ; Creates or replaces the daily task. Throws if Windows refuses.
    static Schedule(startTime) {
        command := DailyTask.SeedCommand()
        DailyTask.Register(DailyTask.NAME, DailyTask.Xml(startTime, command[1], command[2]))
    }

    static Unschedule() {
        if DailyTask.IsScheduled()
            DailyTask.Delete(DailyTask.NAME)
    }

    static IsScheduled() => DailyTask.Exists(DailyTask.NAME)

    ; Registers a task from its XML, replacing one of the same name, to run as
    ; the signed-in user (TASK_CREATE_OR_UPDATE, TASK_LOGON_INTERACTIVE_TOKEN).
    static Register(name, xml) {
        missing := ComValue(0xA, 0x80020004)  ; an omitted COM parameter
        DailyTask._Folder().RegisterTask(name, xml, 6, missing, missing, 3)
    }

    static Delete(name) => DailyTask._Folder().DeleteTask(name, 0)

    static Exists(name) {
        try {
            DailyTask._Folder().GetTask(name)
            return true
        }
        return false
    }
}

XmlEscape(text) => StrReplace(StrReplace(StrReplace(StrReplace(StrReplace(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"), '"', "&quot;"), "'", "&apos;")

; True if two paths name the same file.
SamePath(a, b) {
    full(path) {
        size := DllCall("GetFullPathNameW", "Str", path, "UInt", 0, "Ptr", 0, "Ptr", 0, "UInt")
        if !size
            return path
        buf := Buffer(size * 2)
        DllCall("GetFullPathNameW", "Str", path, "UInt", size, "Ptr", buf, "Ptr", 0, "UInt")
        return StrGet(buf)
    }
    return full(a) = full(b)
}
