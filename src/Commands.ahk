; What SynSeeder.exe does when started with a command (see SynSeeder.ahk).

; The command line as {seed, record, minutes, every, maxMinutes, installTo,
; oldPids, selftest, selftestLog, unknown, passOn}. ``passOn`` is the command
; line minus --install-to and --old-pid, for a new version to carry on with.
ParseArgs(args) {
    opts := {seed: false, record: false, minutes: 10, every: 3, maxMinutes: 0, installTo: "", oldPids: [],
        selftest: false, selftestLog: "selftest.log", unknown: [], passOn: ""}
    i := 1
    nextValue(name) {
        if i >= args.Length
            throw ValueError(name " needs a value")
        return args[++i]
    }
    numeric(name, text) {
        if !IsNumber(text)
            throw ValueError(name " needs a number, not " text)
        return Number(text)
    }
    pass := []
    while i <= args.Length {
        arg := args[i], value := ""
        if RegExMatch(arg, "^(--[\w-]+)=(.*)$", &m)
            arg := m[1], value := m[2]
        take(name) => value != "" ? value : nextValue(name)
        switch arg, true {
            case "--seed":
                opts.seed := true
                pass.Push(arg)
            case "--record":
                opts.record := true
            case "--minutes":
                opts.minutes := numeric(arg, take(arg))
            case "--every":
                opts.every := numeric(arg, take(arg))
            case "--max-minutes":
                opts.maxMinutes := Integer(numeric(arg, take(arg)))
                pass.Push("--max-minutes", opts.maxMinutes)
            case "--install-to":
                opts.installTo := take(arg)
            case "--old-pid":
                opts.oldPids.Push(Integer(numeric(arg, take(arg))))
            case "--selftest":
                opts.selftest := true
                if value != ""
                    opts.selftestLog := value
                else if i < args.Length && SubStr(args[i + 1], 1, 2) != "--"
                    opts.selftestLog := args[++i]
            default:
                opts.unknown.Push(args[i])
        }
        i++
    }
    for item in pass
        opts.passOn .= (A_Index > 1 ? " " : "") QuoteArg(String(item))
    return opts
}

; A seeding run. ``passOn`` is this run's command line for a new version to
; carry on with; ``installTo`` and ``oldPids`` are set when this process is
; that new version.
RunSeed(config, passOn, installTo := "", oldPids := "") {
    if !SeedLock.Claim() {
        Logs.Info("Another seeding run is already going; exiting")
        return 0
    }
    Logs.Info("SynSeeder v" App.VERSION)
    ; Named at once, so Stop seeding in the window can find this run even
    ; while it updates itself.
    stopping := false
    stop() {
        if !stopping
            Logs.Info("Stop requested")
        stopping := true
    }
    SeedLock.Announce(stop)
    try {
        if installTo != ""
            Updater.Install(installTo, oldPids ? oldPids : [])
        else if Updater.UpdateAndHandOver(config, passOn, , () => stopping)
            return 0
    } catch as err {  ; an update going wrong mustn't stop today's seeding
        Logs.Exception("Updating failed; carrying on with this version", err)
    }
    if stopping {
        Logs.Info("Stopped")
        return 0
    }
    if !WinApi.ListenForStopKey(stop)
        Logs.Warning("Another program has Ctrl+Alt+End, so it can't stop this run; use Stop seeding in SynSeeder's window")
    Logs.Info("Seeding. Press Ctrl+Alt+End to stop.")
    clock := SeedClock(() => stopping)
    game := HllGame(config, clock)
    try {
        screen := GameScreen(LoadButtons(), ObjBindMethod(game, "Rect"))
        outcome := Runner.Seed(config, game, screen, ObjBindMethod(ServerStats, "Fetch"), clock)
    } catch SeedStopped {
        Logs.Info("Stopped")
        return 0
    } catch as err {  ; no console in the built exe, so make sure it's logged
        Logs.Exception("Seeding crashed", err)
        return 2
    }
    Logs.Info("Done: " outcome)
    return outcome == Runner.SEEDED || outcome == Runner.ALREADY_SEEDED ? 0 : 1
}

; The button images: downloaded from GitHub into %LOCALAPPDATA% by a built exe
; (checked against ButtonFiles.SHA256), or the repository's templates folder
; when run as a script. A player's own images in %APPDATA%\SynSeeder\templates
; replace the ones of the same button. While GitHub is answering, a built exe
; also gets any of the window's fonts it lacks, for the window's next open.
LoadButtons() {
    if A_IsCompiled {
        folder := Buttons.Folder
        missing := Buttons.Fetch(folder, ButtonFiles.SHA256, Build.COMMIT != "" ? Build.COMMIT : "main")
        if missing.Length
            Logs.Warning("Couldn't get these button images: " JoinList(missing))
        else
            try Look.GetFonts(30)
        crops := Buttons.Load(folder, ButtonFiles.SHA256)
    } else {
        crops := Buttons.Load(A_ScriptDir "\templates")
    }
    crops := Buttons.Merge(crops, Buttons.Load(App.Dir "\templates"))
    names := ""
    for name in crops
        names .= (names = "" ? "" : ", ") name
    Logs.Info("Loaded button images: " (names = "" ? "none" : names))
    missing := Buttons.Missing(crops)
    if missing.Length
        throw Error("Missing button images: " JoinList(missing))
    return crops
}

; Saves a screenshot every ``every`` seconds for ``minutes`` minutes, for making button images.
RunRecord(minutes, every) {
    out := App.Dir "\screenshots\" FormatTime(, "yyyyMMdd-HHmmss")
    DirCreate(out)
    screen := GameScreen(Map())
    Logs.Info("Recording a screenshot every " every "s for " minutes " minutes into " out)
    finish := A_TickCount + minutes * 60000
    n := 0
    while A_TickCount < finish {
        if screen.Refresh() {  ; follows the monitor and warns about black or failed captures
            try {
                screen.SaveScreenshot(out "\" Format("{:04d}", n + 1) ".png")
                n++
            } catch as err {
                Logs.Warning("Couldn't save a screenshot: " err.Message)
            }
        }
        Sleep(Round(every * 1000))
    }
    Logs.Info("Saved " n " screenshots to " out)
    return 0
}
