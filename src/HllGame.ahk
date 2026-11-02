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
    static IDLE_BEFORE_TAKEOVER := 15

    ; ``clock`` paces the waits in Launch, so a stop request ends them.
    __New(config, clock := "") {
        this.config := config
        this.clock := clock ? clock : SeedClock()
        this.focusWait := ""     ; why the game isn't in front, once logged
        this.altTapped := false  ; ForceToFront's Alt tap, used once per wait
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

    ; Starts the game and waits for its window. False on timeout.
    Launch(timeout := "") {
        uri := this.LaunchUri()
        Logs.Info("Launching the game via " uri)
        Run(uri)
        timeout := timeout = "" ? this.config.launch_timeout : timeout
        deadline := this.clock.Now() + timeout
        while this.clock.Now() < deadline {
            if this.Window()
                return true
            this.clock.Sleep(2)
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
        return false
    }

    ; Brings the game to the front. True if it is the foreground window, so
    ; keys and clicks will land in it.
    ;
    ; If someone is using another window, it waits for them: once the mouse
    ; and keyboard have been idle for IDLE_BEFORE_TAKEOVER seconds it takes
    ; the game to the front itself. Meanwhile the game's taskbar button
    ; flashes to show it's waiting.
    Focus() {
        hwnd := this.Window()
        if !hwnd
            return false
        WinApi.SetInputTarget(hwnd)  ; input is dropped whenever this isn't in front
        if WinApi.BringToFront(hwnd) {
            this._InFront()
            return true
        }
        idle := WinApi.UserIdleSeconds()
        if idle >= HllGame.IDLE_BEFORE_TAKEOVER {
            if WinApi.ForceToFront(hwnd, !this.altTapped) {
                Logs.Info("Brought the game to the front (mouse and keyboard idle for " Round(idle) "s)")
                this._InFront()
                return true
            }
            if WinApi.InFront(hwnd)
                return false  ; ours, but still restoring from minimised: ready on the next try
            this.altTapped := true
            wait := "refused"
        } else {
            wait := "in use"
        }
        if wait != this.focusWait {
            if wait = "in use" {
                Logs.Warning("Another window is in front and the PC is in use; waiting until the mouse "
                    . "and keyboard have been idle for " HllGame.IDLE_BEFORE_TAKEOVER "s")
                WinApi.Flash(hwnd)
            } else {
                Logs.Warning("Couldn't bring the game to the front (" HllGame.ForegroundApp() " has it); "
                    . "holding input until it is")
            }
            this.focusWait := wait
        }
        return false
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
    }

    ; True while Focus is holding off because someone is using the PC.
    WaitingForUser() => this.focusWait = "in use"

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
