; SynSeeder trial build in AutoHotkey v2: the parts the real app needs, to
; see whether it scans clean on VirusTotal. Included by full.ahk and
; noupdate.ahk, which add the update check.

#SingleInstance Force

APP_VERSION := "0.9.0"
STATS_URL := "https://syn-stats-nam.radicalgamingstats.com/api/get_public_info"
RELEASE_API := "https://api.github.com/repos/waterjugs/SYN-Seeder/releases/latest"
RELEASE_PAGE := "https://github.com/waterjugs/SYN-Seeder/releases/latest"
STEAM_URI := "steam://rungameid/3079210"
EPIC_APP := "d7361b7d6fa94097bcadeac4b1f785fb"
GAME_EXES := ["HLLVietnam-Win64-Shipping.exe", "HLLVietnamEpicGamesStore-Win64-Shipping.exe"]
DATA_DIR := EnvGet("LOCALAPPDATA") "\SynSeeder"
IMAGE_DIR := DATA_DIR "\images"
SETTINGS_DIR := EnvGet("APPDATA") "\SynSeeder"
SETTINGS := SETTINGS_DIR "\settings.ini"
REQUIRED := ["admin_yes", "game_menu_leave", "deploy_button", "roles_confirm", "switch_team", "server_row"
    , "browser_search", "browser_refresh", "menu_enlist", "browser_join", "faction_nva", "infantry_create"
    , "select_force", "force_us", "force_nva", "create_unit", "create_unit_button"]
; Screens in the order they're checked. Overlays come first.
SCREENS := ["admin_yes", "game_menu_leave", "deploy_button", "roles_confirm", "select_force", "create_unit"
    , "switch_team", "server_row", "browser_search", "browser_refresh", "menu_enlist"]
UI := {}
State := {running: false, stopping: false}

CoordMode "Mouse", "Screen"
CoordMode "Pixel", "Screen"
SendMode "Input"

if A_Args.Length >= 1 && A_Args[1] = "--selftest"
    ExitApp SelfTest(A_Args.Length >= 2 ? A_Args[2] : "selftest.log")
if HandleUpdateArgs()
    ExitApp
InstallImages()
ShowWindow()
for arg in A_Args
    if arg = "--seed"
        SetTimer SeedNow, -1000

; Ctrl+Alt+End stops a run from anywhere, even in game.
^!End::State.stopping := true

; Button images: built into the exe (see images*.ahk), unpacked next to the settings.

; The width and height stored in a PNG's or BMP's header.
ImageSize(path) {
    f := FileOpen(path, "r")
    if SubStr(path, -4) = ".bmp" {
        f.Pos := 18
        w := f.ReadInt(), h := Abs(f.ReadInt())
    } else {
        f.Pos := 16
        w := (f.ReadUChar() << 24) | (f.ReadUChar() << 16) | (f.ReadUChar() << 8) | f.ReadUChar()
        h := (f.ReadUChar() << 24) | (f.ReadUChar() << 16) | (f.ReadUChar() << 8) | f.ReadUChar()
    }
    f.Close()
    return {w: w, h: h}
}

; Where the game draws, or the whole screen while it has no window.
GameArea() {
    for exe in GAME_EXES {
        if hwnd := WinExist("ahk_exe " exe) {
            WinGetClientPos &x, &y, &w, &h, hwnd
            if w > 0 && h > 0
                return {x: x, y: y, w: w, h: h, hwnd: hwnd}
        }
    }
    return {x: 0, y: 0, w: A_ScreenWidth, h: A_ScreenHeight, hwnd: 0}
}

GameRunning() {
    for exe in GAME_EXES
        if ProcessExist(exe)
            return true
    return false
}

; Finds a button image in the game's area, scaled from the 1440p it was cut at.
; Returns {x, y} of its centre, or "" when it isn't showing.
FindImage(name, area) {
    path := IMAGE_DIR "\" name ImageExt()
    size := ImageSize(path)
    w := Round(size.w * area.h / 1440), h := Round(size.h * area.h / 1440)
    try {
        if ImageSearch(&x, &y, area.x, area.y, area.x + area.w - 1, area.y + area.h - 1, "*60 *w" w " *h" h " " path)
            return {x: x + w // 2, y: y + h // 2}
    }
    return ""
}

HttpGet(url, accept := "application/json") {
    req := ComObject("WinHttp.WinHttpRequest.5.1")
    req.Open("GET", url, false)
    req.SetRequestHeader("User-Agent", "SynSeeder/" APP_VERSION " (+https://github.com/waterjugs/SYN-Seeder)")
    req.SetRequestHeader("Accept", accept)
    req.SetTimeouts(5000, 5000, 15000, 30000)
    req.Send()
    if req.Status != 200
        throw Error("HTTP " req.Status " from " url)
    return req
}

; The server's player count from its stats page, or -1 when it can't be read.
PlayerCount() {
    try {
        text := HttpGet(STATS_URL).ResponseText
        if RegExMatch(text, '"player_count"\s*:\s*(\d+)', &m)
            return Integer(m[1])
    }
    return -1
}

; The team with fewer players, allies on a tie.
WeakerSide() {
    try {
        text := HttpGet(STATS_URL).ResponseText
        if RegExMatch(text, '"allied"\s*:\s*(\d+)', &allied) && RegExMatch(text, '"axis"\s*:\s*(\d+)', &axis)
            return Integer(allied[1]) <= Integer(axis[1]) ? "allies" : "axis"
    }
    return "allies"
}

LatestTag() {
    try {
        text := HttpGet(RELEASE_API, "application/vnd.github+json").ResponseText
        if RegExMatch(text, '"tag_name"\s*:\s*"([^"]+)"', &m)
            return m[1]
    }
    return "none published"
}

ShowWindow() {
    g := Gui("-MaximizeBox", "SynSeeder " APP_VERSION)
    g.SetFont("s10", "Segoe UI")
    g.MarginX := 16, g.MarginY := 12
    g.Add("Text", "w340", "Syndicate | Competitive Server")
    g.SetFont("s14 bold")
    UI.Players := g.Add("Text", "w340", "Players: ...")
    g.SetFont("s10 norm")
    g.Add("Text", "xm w150", "Start time")
    UI.Start := g.Add("DateTime", "x+8 w90", "HH:mm")
    UI.Start.Value := A_YYYY A_MM A_DD StrReplace(IniRead(SETTINGS, "seeder", "start_time", "07:00"), ":") "00"
    g.Add("Text", "xm w150", "Seeded at (players)")
    target := IniRead(SETTINGS, "seeder", "seeded_threshold", "80")
    UI.Target := g.Add("Edit", "x+8 w60 Number", target)
    g.Add("UpDown", "Range1-100", target)
    g.Add("Text", "xm w150", "Game launcher")
    UI.Launcher := g.Add("DropDownList", "x+8 w140", ["Steam", "Epic Games"])
    UI.Launcher.Value := IniRead(SETTINGS, "seeder", "launcher", "steam") = "epic" ? 2 : 1
    UI.Daily := g.Add("Checkbox", "xm", "Start every day at this time")
    UI.Daily.Value := TaskExists()
    UI.Daily.OnEvent("Click", (*) => SaveSchedule())
    UI.Seed := g.Add("Button", "xm w110 Default", "Seed now")
    UI.Seed.OnEvent("Click", SeedNow)
    UI.Update := g.Add("Button", "x+8 w160", "Check for updates")
    UI.Update.OnEvent("Click", CheckForUpdates)
    UI.Status := g.Add("Text", "xm w340 r2", "")
    g.OnEvent("Close", (*) => ExitApp())
    UI.Gui := g
    g.Show()
    RefreshPlayers()
    SetTimer RefreshPlayers, 60000
}

RefreshPlayers(*) {
    n := PlayerCount()
    UI.Players.Value := n < 0 ? "Players: unknown" : "Players: " n " / " UI.Target.Value
}

SaveSettings() {
    DirCreate SETTINGS_DIR
    IniWrite FormatTime(UI.Start.Value, "HH:mm"), SETTINGS, "seeder", "start_time"
    IniWrite UI.Target.Value, SETTINGS, "seeder", "seeded_threshold"
    IniWrite UI.Launcher.Value = 2 ? "epic" : "steam", SETTINGS, "seeder", "launcher"
}

SaveSchedule() {
    SaveSettings()
    at := FormatTime(UI.Start.Value, "HH:mm")
    try {
        if UI.Daily.Value {
            ScheduleDaily(at)
            UI.Status.Value := "SynSeeder will start every day at " at "."
        } else {
            Unschedule()
            UI.Status.Value := "Daily start turned off."
        }
    } catch as e {
        UI.Status.Value := "Couldn't change the daily start: " e.Message
    }
}

; The daily start: a scheduled task in the user's own account, never as administrator.
TaskFolder() {
    service := ComObject("Schedule.Service")
    service.Connect()
    return service.GetFolder("\")
}

TaskExists() {
    try {
        TaskFolder().GetTask("SynSeeder")
        return true
    }
    return false
}

ScheduleDaily(startTime) {
    missing := ComValue(0xA, 0x80020004)  ; an omitted COM parameter
    TaskFolder().RegisterTask("SynSeeder", TaskXml(startTime, InstalledCopy()), 6, missing, missing, 3)
}

Unschedule() {
    if TaskExists()
        TaskFolder().DeleteTask("SynSeeder", 0)
}

; The task starts a copy in %LOCALAPPDATA%\SynSeeder, so it keeps working if the download is moved.
InstalledCopy() {
    target := DATA_DIR "\SynSeeder.exe"
    if A_IsCompiled && A_ScriptFullPath != target {
        DirCreate DATA_DIR
        FileCopy A_ScriptFullPath, target, 1
    }
    return target
}

XmlEscape(text) => StrReplace(StrReplace(StrReplace(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;")

TaskXml(startTime, program) {
    start := A_YYYY A_MM A_DD StrReplace(startTime, ":") "00"
    if DateDiff(start, A_Now, "Seconds") <= 0
        start := DateAdd(start, 1, "Days")
    user := EnvGet("USERDOMAIN") "\" A_UserName
    xml := '
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
        <Enabled>true</Enabled>
        <ExecutionTimeLimit>PT6H</ExecutionTimeLimit>
        <Priority>7</Priority>
      </Settings>
      <Actions Context="Author">
        <Exec>
          <Command>{3}</Command>
          <Arguments>--seed</Arguments>
        </Exec>
      </Actions>
    </Task>
    )'
    return Format(xml, FormatTime(start, "yyyy-MM-dd") "T" FormatTime(start, "HH:mm:ss"), XmlEscape(user), XmlEscape(program))
}

EpicUri() {
    try {
        text := FileRead(EnvGet("ProgramData") "\Epic\UnrealEngineLauncher\LauncherInstalled.dat")
        if RegExMatch(text, 's)"NamespaceId"\s*:\s*"(\w+)"[^}]*?"ItemId"\s*:\s*"(\w+)"[^}]*?"AppName"\s*:\s*"(' EPIC_APP ')"', &m)
            return "com.epicgames.launcher://apps/" m[1] "%3A" m[2] "%3A" m[3] "?action=launch&silent=true"
    }
    return "com.epicgames.launcher://apps/" EPIC_APP "?action=launch&silent=true"
}

; Waits, but stops the run if Ctrl+Alt+End or Stop was pressed.
WaitFor(ms) {
    end := A_TickCount + ms
    while A_TickCount < end {
        if State.stopping
            throw Error("stopped")
        Sleep 200
    }
}

SeedNow(*) {
    if State.running {
        State.stopping := true
        return
    }
    State.running := true, State.stopping := false
    UI.Seed.Text := "Stop"
    try {
        Seeding()
    } catch as e {
        UI.Status.Value := "Stopped: " e.Message
    }
    State.running := false
    UI.Seed.Text := "Seed now"
}

Seeding() {
    target := Integer(UI.Target.Value)
    n := PlayerCount()
    if n >= target {
        UI.Status.Value := "Already seeded (" n " players)."
        return
    }
    if !GameRunning() {
        Run UI.Launcher.Value = 2 ? EpicUri() : STEAM_URI
        deadline := A_TickCount + 300000
        while !GameRunning() {
            if A_TickCount > deadline
                throw Error("the game didn't start")
            WaitFor(2000)
        }
    }
    started := A_TickCount
    while A_TickCount - started < 4 * 3600 * 1000 {
        n := PlayerCount()
        if n >= target {
            UI.Status.Value := "Seeded. Leaving the server."
            WaitFor(Random(0, 600) * 1000)
            CloseGame()
            return
        }
        UI.Status.Value := (n < 0 ? "?" : n) " of " target " players"
        loop 15 {
            if Focus()
                Step()
            WaitFor(2000)
        }
    }
}

; Brings the game in front, but only once nobody has used the PC for 15 seconds.
Focus() {
    area := GameArea()
    if !area.hwnd
        return false
    if WinActive(area.hwnd)
        return true
    if A_TimeIdle < 15000
        return false
    try WinActivate area.hwnd
    return WinWaitActive(area.hwnd, , 2) != 0
}

; Works out which menu is showing and does the one thing that moves it forward.
Step() {
    area := GameArea()
    for name in SCREENS {
        if pos := FindImage(name, area) {
            Handle(name, pos, area)
            return name
        }
    }
    return ""
}

Handle(name, pos, area) {
    switch name {
        case "admin_yes", "menu_enlist":
            ClickAt(pos)
        case "game_menu_leave":
            Send "{Esc}"
        case "deploy_button", "roles_confirm":
            Send "f"
        case "select_force":
            card := WeakerSide() = "axis" ? FindImage("force_nva", area) : FindImage("force_us", area)
            if card
                ClickAt(card)
        case "create_unit":
            if button := FindImage("create_unit_button", area)
                ClickAt(button)
        case "switch_team":
            ; Always lead a new squad of our own, never join someone else's.
            if button := FindImage("infantry_create", area)
                ClickAt(button)
        case "server_row":
            if join := FindImage("browser_join", area)
                ClickAt({x: join.x, y: pos.y})
        case "browser_search":
            ClickAt(pos)
            Sleep 500
            SendText "syndicate"
            Send "{Enter}"
        case "browser_refresh":
            Send "r"
    }
}

ClickAt(pos) {
    Click pos.x, pos.y
    Sleep 100
    MouseMove 5, A_ScreenHeight // 2, 0  ; so hover highlights don't change the next match
}

CloseGame() {
    for exe in GAME_EXES {
        if ProcessExist(exe) {
            WinClose "ahk_exe " exe
            if !ProcessWaitClose(exe, 30)
                ProcessClose exe
        }
    }
}

; "SynSeeder.exe --selftest LOG" checks the parts that don't need the game. CI runs it on every build.
SelfTest(logPath) {
    OnError(SelfTestError)
    SelfTestError(e, mode) {
        FileAppend "ERROR " e.Message " (line " e.Line ")`n", logPath, "UTF-8"
        ExitApp 2
    }
    lines := []
    ok := true
    InstallImages()
    missing := ""
    for name in REQUIRED
        if !FileExist(IMAGE_DIR "\" name ImageExt())
            missing .= " " name
    lines.Push((missing = "" ? "PASS" : "FAIL") " button images" missing)
    ok := ok && missing = ""
    size := ImageSize(IMAGE_DIR "\select_force" ImageExt())
    good := size.w = 483 && size.h = 59
    lines.Push((good ? "PASS" : "FAIL") " image size " size.w "x" size.h)
    ok := ok && good
    xml := TaskXml("07:30", "C:\A & B\SynSeeder.exe")
    good := InStr(xml, "<Command>C:\A &amp; B\SynSeeder.exe</Command>") && InStr(xml, "T07:30:00</StartBoundary>")
    lines.Push((good ? "PASS" : "FAIL") " daily task XML")
    ok := ok && good
    lines.Push("     players: " PlayerCount())
    lines.Push("     latest release: " LatestTag())
    lines.Push("     game area: " GameArea().w "x" GameArea().h ", idle " A_TimeIdle " ms")
    lines.Push(ok ? "SELFTEST OK" : "SELFTEST FAILED")
    out := ""
    for line in lines
        out .= line "`n"
    if FileExist(logPath)
        FileDelete logPath
    FileAppend out, logPath, "UTF-8"
    return ok ? 0 : 1
}
