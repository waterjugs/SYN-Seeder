; Starting, finding, focusing and closing the game.

class HllGame {
    ; Used when process_name is blank: any HLL build.
    static DEFAULT_PATTERN := "i)^HLL.*-Win64-Shipping\.exe$"
    ; HLL Vietnam's game process in the Steam and the Epic build (seen
    ; 2026-10-30). A process_name of either means the game from whichever
    ; store started it.
    static PROCESSES := ["HLLVietnam-Win64-Shipping.exe", "HLLVietnamEpicGamesStore-Win64-Shipping.exe"]
    static EPIC_APP_NAME := "d7361b7d6fa94097bcadeac4b1f785fb"  ; HLL Vietnam's AppName in the Epic store (2026-10-29)
    ; Seconds without mouse or keyboard use before the seeder pulls the game in
    ; front of whatever someone was doing; until then it waits for them.
    ; Someone reading or watching a video can leave both alone for a while, so
    ; this is long (before version 1.1.0 it was 15 s, which cut in on them).
    static IDLE_BEFORE_TAKEOVER := 300
    ; Seconds without mouse or keyboard use before the seeder takes the front
    ; when no other program's window has it, or carries on after the game came
    ; back to the front during a wait (see Focus).
    static SETTLE_SECONDS := 10
    ; Seconds to keep watching for a game the launcher starts late, to close it.
    static LATE_START_SECONDS := 90

    ; ``clock`` paces the waits in Launch, so a stop request ends them.
    ; ``lateClock`` paces the watch for a late start after a stop, which the
    ; stopped clock can't (tests pass their own).
    __New(config, clock := "", lateClock := "") {
        this.config := config
        this.clock := clock ? clock : SeedClock()
        this.lateClock := lateClock ? lateClock : SeedClock()
        this.focusWait := ""     ; why the game isn't in front, once logged
        this.altTapped := false  ; ForceToFront's Alt tap, used once per wait
        this.switching := ""     ; how a switch to the game that's still restoring was made, for the log
        this.cameBack := false   ; the game came back to the front by itself during a wait, and the log said so
        this.hadFront := false   ; the game has been in front in this run
        ; True from a launch that timed out until the next one: the launcher
        ; can still start the game (see Runner.Seed).
        this.launchPending := false
    }

    static EpicManifest {
        get {
            base := EnvGet("PROGRAMDATA")
            return (base != "" ? base : "C:\ProgramData") "\Epic\UnrealEngineLauncher\LauncherInstalled.dat"
        }
    }

    ; Finds HLL Vietnam in the Epic launcher's install list, as
    ; namespace:item:app like Epic's own shortcuts use, or "" when it isn't installed.
    static DetectEpicAppName(manifest := "") {
        manifest := manifest != "" ? manifest : HllGame.EpicManifest
        try
            data := Json.Load(FileRead(manifest, "UTF-8"))
        catch
            return ""
        if !(data is Map) || !data.Has("InstallationList") || !(data["InstallationList"] is Array)
            return ""
        field(entry, key) {
            value := entry.Has(key) ? entry[key] : ""
            return IsObject(value) ? "" : String(value)
        }
        byAppName(entry) => field(entry, "AppName") == HllGame.EPIC_APP_NAME
        byFolder(entry) {  ; Epic picks the folder name, e.g. Hell_Let_Loose_Vietnam
            folder := RegExReplace(StrLower(field(entry, "InstallLocation")), "[^a-z0-9]")
            return InStr(folder, "hellletloose") && InStr(folder, "vietnam")
        }
        for match in [byAppName, byFolder] {
            for entry in data["InstallationList"] {
                if !(entry is Map) || field(entry, "AppName") = "" || !match(entry)
                    continue
                ids := [field(entry, "NamespaceId"), field(entry, "ItemId"), field(entry, "AppName")]
                return ids[1] != "" && ids[2] != "" ? JoinList(ids, ":") : ids[3]
            }
        }
        return ""
    }

    static _Known(name) {
        for exe in HllGame.PROCESSES
            if exe = name
                return true
        return false
    }

    ; True if a program named ``name`` is the game.
    Matches(name) {
        wanted := Trim(this.config.process_name)
        if wanted = ""  ; a hand-edited blank (or null) means any HLL build
            return RegExMatch(name, HllGame.DEFAULT_PATTERN) > 0
        if HllGame._Known(wanted)  ; the saved default, Steam's name, must also find the Epic game
            return HllGame._Known(name)
        return name = wanted
    }

    ; The game's process ID, or 0 when it isn't running.
    Pid() {
        wanted := Trim(this.config.process_name)
        for exe in wanted = "" || HllGame._Known(wanted) ? HllGame.PROCESSES : [wanted]
            if pid := ProcessExist(exe)
                return pid
        if wanted = ""  ; any HLL build: look through the programs with windows
            for item in HllGame.WindowedProcesses()
                if this.Matches(item.name)
                    return item.pid
        return 0
    }

    ; {pid, name} of each program with a top-level window.
    static WindowedProcesses() {
        out := [], seen := Map()
        prev := DetectHiddenWindows(true)
        try {
            for hwnd in WinGetList() {
                try {
                    pid := WinGetPID(hwnd)
                    if seen.Has(pid)
                        continue
                    seen[pid] := true
                    out.Push({pid: pid, name: WinGetProcessName(hwnd)})
                }
            }
        } finally {
            DetectHiddenWindows(prev)
        }
        return out
    }

    Running() => this.Pid() != 0

    Unlocked() => WinApi.DesktopUnlocked()

    Window() {
        pid := this.Pid()
        return pid ? WinApi.MainWindow(pid) : 0
    }

    ; Where the game is drawn on screen: [left, top, width, height], or "".
    Rect() {
        hwnd := this.Window()
        return hwnd ? WinApi.ClientRect(hwnd) : ""
    }

    LaunchUri() {
        if this.config.launcher = "epic" {
            app := this.config.epic_app_name != "" ? this.config.epic_app_name : HllGame.DetectEpicAppName()
            if app = ""
                throw Error("Couldn't find HLL Vietnam in the Epic launcher")
            ; unquote first: a value copied from an Epic shortcut already has %3A in it
            return "com.epicgames.launcher://apps/" UriQuote(UriUnquote(Trim(app))) "?action=launch&silent=true"
        }
        return "steam://rungameid/" this.config.steam_app_id
    }

    ; Asks Steam or Epic to start the game.
    static Start(uri) => Run(uri)

    ; Starts the game and waits for its window. False on timeout, and then
    ; launchPending is set. A stop asked for before the game shows up still
    ; closes it if it starts within LATE_START_SECONDS.
    Launch(timeout := "") {
        uri := this.LaunchUri()
        this.clock.Check()  ; already asked to stop: don't start it
        Logs.Info("Launching the game via " uri)
        this.launchPending := false  ; this launch's own wait covers the last one's
        HllGame.Start(uri)
        timeout := timeout = "" ? this.config.launch_timeout : timeout
        deadline := this.clock.Now() + timeout
        try {
            while this.clock.Now() < deadline {
                if this.Window()
                    return true
                this.clock.Sleep(2)
            }
        } catch SeedStopped as stop {
            this.CloseLateStart(HllGame.LATE_START_SECONDS)  ; the launcher can still start it after the timeout
            throw stop
        }
        names := Map()
        for item in HllGame.WindowedProcesses()
            if SubStr(item.name, 1, 3) = "hll"
                names[item.name] := true
        list := []
        for name in names
            list.Push(name)
        Logs.Error("The game window didn't appear within " Round(timeout) "s (HLL programs with a window: "
            . (list.Length ? JoinList(list) : "none") ")")
        this.launchPending := true
        return false
    }

    ; Brings the game to the front. True if it is the foreground window, so
    ; keys and clicks will land in it.
    ;
    ; If another program's window is in front, someone may be using it, so it
    ; waits for them: once the mouse and keyboard have been idle for
    ; IDLE_BEFORE_TAKEOVER seconds it takes the game to the front itself.
    ; Meanwhile the game's taskbar button flashes to show it's waiting. It
    ; doesn't even ask Windows to switch before then, because Windows doesn't
    ; always say no while someone uses another window: once the mouse and
    ; keyboard have been idle for its foreground lock timeout (200 s by
    ; default, less on some PCs) it lets any program take the front.
    ;
    ; When no other program's window is in front (nothing is, another of the
    ; game's, or SynSeeder's own until the game has been in front once, as
    ; after Seed now), it takes the front once the mouse and keyboard have
    ; been still for SETTLE_SECONDS. The same goes for a game someone
    ; minimised that's still the window in front (Windows had nothing else to
    ; switch to). And when the game comes back to the front during a wait
    ; without SynSeeder (the player clicked it, or Windows switched to it
    ; because they minimised or closed their window), it sends nothing until
    ; they've been still that long too.
    Focus() {
        hwnd := this.Window()
        if !hwnd
            return false
        WinApi.SetInputTarget(hwnd)  ; input is dropped whenever this isn't in front
        front := WinApi.ForegroundWindow()
        idle := WinApi.UserIdleSeconds()
        minimised := front = hwnd && this.switching = "" && WinApi.IsMinimised(hwnd)  ; by someone, not SynSeeder
        if front = hwnd && !minimised {
            if this.switching = "" && this.focusWait != "" {  ; any wait, a refused takeover too (as before an unlock)
                if !this.cameBack
                    Logs.Info("The game is in front again, but not because of SynSeeder: you switched to it, "
                        . "or Windows or the game did (mouse and keyboard last used " Round(idle) "s ago)")
                this.cameBack := true
                if idle < HllGame.SETTLE_SECONDS
                    return false  ; someone is at the PC: don't click or type under their hands
            }
            if !WinApi.BringToFront(hwnd)
                return false  ; in front, but still restoring from minimised: ready on the next try
            if this.switching != ""
                Logs.Info("Brought the game to the front (" this.switching ")")
            this._InFront()
            return true
        }
        this.switching := "", this.cameBack := false  ; not in front (any more)
        free := minimised || HllGame.FrontIsFree(front, hwnd, !this.hadFront)
        need := free ? HllGame.SETTLE_SECONDS : HllGame.IDLE_BEFORE_TAKEOVER
        if idle >= need {
            how := (free ? HllGame._FreeFront(front, hwnd) "; " : "") "mouse and keyboard idle for " HllGame.Span(idle)
            if WinApi.ForceToFront(hwnd, !this.altTapped) {
                Logs.Info("Brought the game to the front (" how ")")
                this._InFront()
                return true
            }
            if WinApi.InFront(hwnd) {
                this.switching := how  ; ours, but still restoring from minimised: ready on the next try
                return false
            }
            this.altTapped := true
            wait := "refused"
        } else {
            wait := free ? "busy" : "in use"
        }
        if wait != this.focusWait {
            if wait = "refused" {
                Logs.Warning("Couldn't bring the game to the front (" HllGame.ForegroundApp() " has it); "
                    . "holding input until it is")
            } else {
                if free
                    why := "The PC is in use"
                else if !front
                    why := "The PC is locked, or a Windows prompt is up"
                else {
                    name := HllGame._FrontName(front)
                    why := "Another program's window is in front" (name != "" ? " (" name ")" : "") " and the PC is in use"
                }
                Logs.Warning(why "; waiting until the mouse and keyboard have been idle for " HllGame.Span(need))
                WinApi.Flash(hwnd)
            }
            this.focusWait := wait
        }
        return false
    }

    ; True if the game can come to the front without taking it from another
    ; program: no window is in front (``front`` is 0) and the PC isn't locked,
    ; or one of the game's own windows is, or with ``ownToo`` one of
    ; SynSeeder's (its window, after Seed now). Another program's window may
    ; be in use.
    static FrontIsFree(front, game, ownToo := true) {
        if front = game
            return true
        if !front  ; also while the PC is locked or a UAC prompt is up
            return WinApi.DesktopUnlocked()
        pid := WinApi.WindowPid(front)
        if !pid
            return false
        if pid = WinApi.WindowPid(game)
            return true
        if !ownToo
            return false
        name := WinApi.ProcessName(pid)  ; SynSeeder.exe, or "SynSeeder (1).exe" if downloaded twice
        return name != "" && (name = WinApi.ProcessName(WinApi.OwnPid()) || name ~= "i)^SynSeeder\b.*\.exe$")
    }

    ; What was in front when FrontIsFree said yes, for the log.
    static _FreeFront(front, game) {
        if !front
            return "no window was in front"
        if front = game
            return "the game was minimised"
        return WinApi.WindowPid(front) = WinApi.WindowPid(game) ? "another of its windows was in front"
            : "SynSeeder's window was in front"
    }

    ; The program whose window ``front`` is, for the log, or "".
    static _FrontName(front) {
        pid := front ? WinApi.WindowPid(front) : 0
        return pid ? WinApi.ProcessName(pid) : ""
    }

    ; ``seconds`` for the log: "10 s", "5 min", "5 min 12 s".
    static Span(seconds) {
        seconds := Round(seconds)
        if seconds < 60
            return seconds " s"
        return Mod(seconds, 60) ? MinutesText(seconds) : seconds // 60 " min"
    }

    ; Name of the program whose window is in front, for the log.
    static ForegroundApp() {
        pid := WinApi.ForegroundPid()
        if !pid
            return "no window"
        try
            return ProcessGetName(pid)
        catch
            return "another program"
    }

    _InFront() {
        this.focusWait := ""
        this.altTapped := false
        this.switching := ""
        this.cameBack := false
        this.hadFront := true
    }

    ; True while Focus is holding off because someone is using the PC.
    WaitingForUser() => this.focusWait = "in use" || this.focusWait = "busy"

    ; Ends the game. With ``linger``, keeps watching that long for a late
    ; start (Steam can take minutes to launch after an update). A stop
    ; request ends the watching, not the closing.
    Close(linger := 0) {
        deadline := this.clock.Now() + linger
        loop {
            pid := this.Pid()
            if pid
                HllGame._End(pid)
            if this.clock.Now() >= deadline
                return
            try
                this.clock.Sleep(5)
            catch SeedStopped
                return
        }
    }

    ; After a stop while the launcher was starting the game: watches up to
    ; ``seconds`` for the game and closes it if it shows up.
    CloseLateStart(seconds) {
        if this.Pid() {
            this.Close()
            return
        }
        if seconds <= 0
            return
        Logs.Info("Watching up to " Round(seconds) " s for the game the launcher is starting, to close it")
        endAt := this.lateClock.Now() + seconds
        while this.lateClock.Now() < endAt {
            this.lateClock.Sleep(2)
            if pid := this.Pid() {
                HllGame._End(pid)
                return
            }
        }
    }

    static _End(pid) {
        Logs.Info("Closing the game")
        if !ProcessClose(pid) && ProcessExist(pid) {
            Logs.Error("Can't close the game: it's running as administrator. Close it yourself, "
                . "and don't run Steam as administrator.")
            return
        }
        ProcessWaitClose(pid, 30)
    }
}
