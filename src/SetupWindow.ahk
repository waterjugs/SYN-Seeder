; The window you get by double-clicking SynSeeder.exe: the server's player
; count, the daily start time, Steam or Epic, Seed when pinged and its hours,
; and buttons to save, seed now and stop seeding. Laid out like the first (Python) SynSeeder's window;
; positions are in pixels at 100% scaling and grow with Windows' scaling.

class SetupWindow {
    static HOURS := ["00", "01", "02", "03", "04", "05", "06", "07", "08", "09", "10", "11"
        , "12", "13", "14", "15", "16", "17", "18", "19", "20", "21", "22", "23"]
    static MINUTES := ["00", "05", "10", "15", "20", "25", "30", "35", "40", "45", "50", "55"]
    static PLAYERS_MAX := 100
    static SERVER_REFRESH_MS := 30000  ; how often the player count is fetched again while the window is open
    static SERVER_TIMEOUT_MS := 15000
    static SEED_CHECK_MS := 3000       ; how often the window looks for a run, so its status line stays true
    static STOP_WAIT := 20             ; seconds a run gets to close the game and end, before it's ended
    static START_GRACE_MS := 2000      ; for a run Seed now just started to name its window
    static CHECKING := "Checking the server..."
    static UNREACHABLE := "Couldn't reach the server stats."

    ; ``live`` shows the window and starts its timers (tests leave it off);
    ; ``scale`` overrides the screen's scaling (tests).
    __New(config, live := true, scale := "") {
        this.config := config
        this.count := ""          ; the player count on show; "" until it's known
        this.note := SetupWindow.CHECKING
        this.seeding := ""        ; whether a run was going at the last look ("" until looked)
        this.spawned := 0         ; the run Seed now started
        this.busy := false        ; Stop seeding is waiting for runs to end
        this.lateWatch := ""      ; after a stop that had to end a run: the timer watching for a late game
        this.exitAfterWatch := false  ; the window was closed during that watch: exit when it ends
        this.request := ""        ; the player-count request in flight
        this.requestAt := 0
        this.picker := ""         ; the open grid of hours or minutes
        this.pickerClosed := ["", 0]
        parts := StrSplit(config.start_time, ":")
        this.hour := parts.Length = 2 && IsInteger(parts[1]) && parts[1] >= 0 && parts[1] < 24 ? Format("{:02d}", parts[1]) : "07"
        this.minute := parts.Length = 2 && SetupWindow._Has(SetupWindow.MINUTES, parts[2]) ? parts[2] : "00"
        this.launcher := config.launcher = "epic" ? "epic" : "steam"
        this.enabled := DailyTask.IsScheduled()
        ; Ticked only if the settings say so and the task is there: an older
        ; SynSeeder's Save drops the setting but leaves the task.
        this.pinged := SeedCalls.On(config) && DailyTask.CallsScheduled()
        this.pingFrom := SetupWindow._Hour(config.pinged_from, "08")
        this.pingUntil := SetupWindow._Hour(config.pinged_until, "23")
        Look.scale := scale != "" ? scale : A_ScreenDPI / 96
        this._Build()
        this.Status(this.ScheduleText())
        this.pollTimer := ObjBindMethod(this, "PollServer")
        if live {
            this.Show()
            this.RefreshServer()
            SetTimer(ObjBindMethod(this, "RefreshServer"), SetupWindow.SERVER_REFRESH_MS)
            this.WatchSeed()
            SetTimer(ObjBindMethod(this, "WatchSeed"), SetupWindow.SEED_CHECK_MS)
            OnMessage(0x100, ObjBindMethod(this, "_Key"))       ; WM_KEYDOWN
            OnMessage(0x200, ObjBindMethod(this, "_GridMove"))  ; WM_MOUSEMOVE
            OnMessage(0x6, ObjBindMethod(this, "_Activate"))    ; WM_ACTIVATE
            Persistent()
        }
    }

    ; The look

    _Build() {
        px(n) => Look.Px(n)
        Look.LoadFonts()
        text := Look.PickFace("Inter", "Segoe UI", "Tahoma")
        bold := text = "Inter" ? ["Inter", 700] : [Look.PickFace("Segoe UI Semibold", "Tahoma"), 600]
        title := Look.PickFace("Barlow Condensed SemiBold", "Bahnschrift SemiBold Condensed", "Segoe UI Semibold", "Tahoma")
        f := this.fonts := {
            body: Font(text, 10),
            small: Font(text, 9),
            semibold: Font(bold[1], 10, bold[2]),
            count: Font(bold[1], 14, bold[2]),
            link: Font(text, 9, 400, true),
            title: Font(title, 0, 0, false, px(Look.TITLE_SIZE))
        }

        g := this.gui := Gui("-MaximizeBox -DPIScale", "SYN Vietnam Seeder")
        g.BackColor := Look.Hex(Look.TWILIGHT)
        g.MarginX := 0, g.MarginY := 0
        g.OnEvent("Close", (*) => this.Close())
        g.OnEvent("Size", (gui, minMax, *) => minMax = 0 ? this._FitWindow() : "")  ; e.g. restored
        g.OnEvent("Escape", (*) => this.ClosePicker())
        W := this.width := px(Look.HEADER_W), M := px(24), CW := this.contentWidth := W - 2 * M, pad := px(2)
        line := Max(1, px(1))

        ; The header, drawn once
        header := this.header := Canvas(W, px(Look.HEADER_H))
        Paint.Header(header, f.title)
        this._Drawn(g.Add("Text", "x0 y0 w" W " h" header.h " +0xD"), (c, st) => header.Paint(c.dc))

        ; The server, and how far it is from seeded
        y := header.h + px(18)
        this._Label(f.semibold, Look.HAZE, M + pad, y + pad, CW - 2 * pad, this.config.server_name)
        y += f.semibold.height + 2 * pad + px(2)
        this.countLine := f.count.height + 2 * pad
        this.players := this._Drawn(g.Add("Text", "x" M " y" y " w" CW " h" (this.countLine + px(6) + px(32)) " +0xD")
            , (c, st) => Paint.Players(c, f, this.count, this.note, this.config.seeded_threshold, SetupWindow.PLAYERS_MAX, this.countLine))
        y += this.countLine + px(6) + px(32) + px(10)

        ; When and how to seed: a row each, the setting on the left and its control against the right edge
        rowH := px(46), rows := []
        loop 5 {
            this._Rule(M, y, CW, line)
            rows.Push(y + line)
            y += line + rowH
        }
        this._Rule(M, y, CW, line)
        baseline(rowTop) => rowTop + Ceil((rowH - f.body.height) / 2) + f.body.ascent

        top := rows[1]
        this._Label(f.body, Look.HAZE, M + pad, baseline(top) - f.body.ascent, f.body.Width("Seed every day at") + 2, "Seed every day at")
        fieldW := px(59), fieldH := px(30), fieldY := top + (rowH - fieldH) // 2
        minuteX := M + CW - fieldW
        colonW := f.semibold.Width(":") + 2 * pad
        colonX := minuteX - px(6) - colonW
        hourX := colonX - px(6) - fieldW
        clockW := f.body.Width("12:55 PM") + 2 * pad
        this.clock := this._Label(f.body, Look.MIST, hourX - px(12) - pad - clockW, baseline(top) - f.body.ascent, clockW, "", "Right")
        this.hourField := this._Button(hourX, fieldY, fieldW, fieldH, this.hour, (c, st) => Paint.Field(c, this.hour, f.body, st), (*) => this.OpenPicker("hour"))
        this._Label(f.semibold, Look.HAZE, colonX, baseline(top) - f.semibold.ascent, colonW, ":", "Center")
        this.minuteField := this._Button(minuteX, fieldY, fieldW, fieldH, this.minute, (c, st) => Paint.Field(c, this.minute, f.body, st), (*) => this.OpenPicker("minute"))
        this.ShowClock()

        top := rows[2]
        this._Label(f.body, Look.HAZE, M + pad, baseline(top) - f.body.ascent, f.body.Width("Game launcher") + 2, "Game launcher")
        chipW := px(78), chipH := px(30), chipY := top + (rowH - chipH) // 2
        epicX := M + CW - chipW, steamX := epicX - px(6) - chipW
        this.steamChip := this._Button(steamX, chipY, chipW, chipH, "Steam", (c, st) => Paint.Chip(c, "Steam", f.body, this.launcher = "steam", st), (*) => this.ChooseLauncher("steam"))
        this.epicChip := this._Button(epicX, chipY, chipW, chipH, "Epic", (c, st) => Paint.Chip(c, "Epic", f.body, this.launcher = "epic", st), (*) => this.ChooseLauncher("epic"))

        top := rows[3]  ; the whole row ticks it
        this.autoBox := this._Button(M, top, CW, rowH, "Seed automatically"
            , (c, st) => Paint.Check(c, "Seed automatically", f.body, this.enabled, st, baseline(0)), (*) => this.ToggleAutomatic())

        top := rows[4]
        this.pingBox := this._Button(M, top, CW, rowH, "Seed when pinged"
            , (c, st) => Paint.Check(c, "Seed when pinged", f.body, this.pinged, st, baseline(0)), (*) => this.TogglePinged())

        top := rows[5]  ; laid out like the first row
        this._Label(f.body, Look.HAZE, M + pad, baseline(top) - f.body.ascent, f.body.Width("Only between") + 2, "Only between")
        fieldY := top + (rowH - fieldH) // 2
        untilX := M + CW - fieldW
        andW := f.body.Width("and") + 2 * pad
        andX := untilX - px(6) - andW
        fromX := andX - px(6) - fieldW
        rangeW := f.body.Width("12 AM " Chr(0x2013) " 12 PM") + 2 * pad
        this.pingClock := this._Label(f.body, Look.MIST, fromX - px(12) - pad - rangeW, baseline(top) - f.body.ascent, rangeW, "", "Right")
        this.pingFromField := this._Button(fromX, fieldY, fieldW, fieldH, this.pingFrom, (c, st) => Paint.Field(c, this.pingFrom, f.body, st), (*) => this.OpenPicker("pingFrom"))
        this._Label(f.body, Look.HAZE, andX, baseline(top) - f.body.ascent, andW, "and", "Center")
        this.pingUntilField := this._Button(untilX, fieldY, fieldW, fieldH, this.pingUntil, (c, st) => Paint.Field(c, this.pingUntil, f.body, st), (*) => this.OpenPicker("pingUntil"))
        this.ShowPingHours()
        y += line + px(20)

        ; Actions: three equal buttons across the width
        gap := px(8), buttonH := px(32), colW := (CW - 2 * gap) / 3
        for i, item in [["Save", true, "Save"], ["Seed now", false, "SeedNow"], ["Stop seeding", false, "StopSeeding"]] {
            x0 := Round((i - 1) * (colW + gap)), x1 := Round((i - 1) * (colW + gap) + colW)
            label := item[1], primary := item[2]
            this._Button(M + x0, y, x1 - x0, buttonH, label, SetupWindow._ButtonPainter(label, f.semibold, primary), ObjBindMethod(this, item[3]))
        }
        y += buttonH + px(12)

        ; What's happening, on two lines so nothing jumps (more for a long message, see Status)
        g.SetFont(f.body.Options(Look.MIST), f.body.face)
        this.statusW := CW - 2 * pad, this.statusH := this.statusMinH := 2 * f.body.height
        this.statusLine := g.Add("Text", "x" (M + pad) " y" (y + pad) " w" this.statusW " h" this.statusH " Center +0x80", "")
        y += 2 * f.body.height + 2 * pad + px(14)
        this._Rule(M, y, CW, line)
        y += line + px(10)

        ; Footer: version, the stop key, the log; then the legal links
        top := y + pad
        version := "v" App.VERSION
        this._Label(f.small, Look.MIST, M + pad, top, f.small.Width(version) + 2, version)
        hint := "Ctrl+Alt+End stops a run", hintW := f.small.Width(hint) + 2
        this._Label(f.small, Look.MIST, (W - hintW) // 2, top, hintW, hint)
        logW := f.link.Width("Open log") + 2
        this._Link(M + CW - pad - logW, top, "Open log", ObjBindMethod(this, "OpenLog"))
        y += f.small.height + 2 * pad + px(6)
        top := y + pad
        termsW := f.link.Width("Terms of Service") + 2, privacyW := f.link.Width("Privacy Policy") + 2, dotW := f.small.Width("·") + 2
        x := (W - (termsW + 2 * pad + px(6) + dotW + 2 * pad + px(6) + privacyW)) // 2
        this._Link(x, top, "Terms of Service", (*) => this.Open(App.TERMS_URL))
        x += termsW + pad + px(6) + pad
        this._Label(f.small, Look.MIST, x, top, dotW, "·")
        x += dotW + pad + px(6) + pad
        this._Link(x, top, "Privacy Policy", (*) => this.Open(App.PRIVACY_URL))
        y += f.small.height + 2 * pad + px(14)
        this.height := y
    }

    static _ButtonPainter(label, font, primary) => (c, st) => Paint.Button(c, label, font, primary, st)

    ; A label: plain text in ``font`` and colour ``rgb``.
    _Label(font, rgb, x, y, w, text, align := "") {
        this.gui.SetFont(font.Options(rgb), font.face)
        return this.gui.Add("Text", "x" Round(x) " y" Round(y) " w" Round(w) " h" font.height " +0x80 " align, text)
    }

    ; A link that does ``action`` when clicked.
    _Link(x, y, text, action) {
        ctrl := this._Label(this.fonts.link, Look.FIRST_LIGHT, x, y, this.fonts.link.Width(text) + 2, text)
        ctrl.OnEvent("Click", action)
        return Skin.Link(ctrl, this.fonts.link, Look.FIRST_LIGHT, Look.LINK_HOVER)
    }

    ; A hairline.
    _Rule(x, y, w, h) => this.gui.Add("Text", "x" x " y" y " w" w " h" h " Background" Look.Hex(Look.EDGE))

    ; A control the window draws itself.
    _Drawn(ctrl, paint) => Skin.Add(ctrl, paint)

    ; A button the window draws itself; ``text`` is what screen readers say.
    _Button(x, y, w, h, text, paint, action) {
        ctrl := this.gui.Add("Button", "x" Round(x) " y" Round(y) " w" Round(w) " h" Round(h), text)
        SendMessage(0xF4, 0xB, true, ctrl)  ; BM_SETSTYLE: BS_OWNERDRAW (AHK resets the style it's created with)
        ctrl.OnEvent("Click", action)
        ctrl.OnEvent("DoubleClick", action)  ; drawn buttons report a quick second click as a double click
        return Skin.Add(ctrl, paint)
    }

    ; The work area (the screen less the taskbar) of the monitor the rectangle
    ; is on, or nearest to: {left, top, right, bottom}.
    static WorkAreaAt(left, top, right, bottom) {
        rect := Buffer(16, 0)
        NumPut("Int", left, "Int", top, "Int", right, "Int", bottom, rect)
        info := Buffer(40, 0)  ; MONITORINFO
        NumPut("UInt", 40, info)
        monitor := DllCall("MonitorFromRect", "Ptr", rect, "UInt", 2, "Ptr")  ; MONITOR_DEFAULTTONEAREST
        if monitor && DllCall("GetMonitorInfoW", "Ptr", monitor, "Ptr", info)
            return {left: NumGet(info, 20, "Int"), top: NumGet(info, 24, "Int"),
                right: NumGet(info, 28, "Int"), bottom: NumGet(info, 32, "Int")}
        MonitorGetWorkArea(MonitorGetPrimary(), &l, &t, &r, &b)
        return {left: l, top: t, right: r, bottom: b}
    }

    ; Centres the window a third of the way down the screen, darkens its title bar, then shows it.
    Show() {
        g := this.gui
        g.Show("Hide w" this.width " h" this.height)
        WinGetPos(, , &w, &h, g)
        MonitorGetWorkArea(MonitorGetPrimary(), &left, &top, &right, &bottom)
        SetupWindow.DressForWindows(g.Hwnd)
        g.Show("x" Max(left, left + (right - left - w) // 2) " y" Max(top, top + (bottom - top - h) // 3))
        SendMessage(0x127, 0x30001, 0, g)  ; WM_CHANGEUISTATE: no focus rings until a key is pressed
        DllCall("SetFocus", "Ptr", g.Hwnd)  ; and nothing picked out until then: Tab goes to the first control
    }

    ; A dark title bar (Windows 10 1809 and later) that Windows 11 also
    ; colours like the header's sky, and SynSeeder's icon when run as a script.
    ; Only looks: if any of it fails, the window opens as it is.
    static DressForWindows(hwnd) {
        value := Buffer(4, 0)
        try {
            NumPut("Int", 1, value)
            if DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 20, "Ptr", value, "UInt", 4)  ; DWMWA_USE_IMMERSIVE_DARK_MODE
                DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 19, "Ptr", value, "UInt", 4)  ; before Windows 10 20H1
            NumPut("UInt", Look.ColorRef(Look.NIGHT), value)
            DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 35, "Ptr", value, "UInt", 4)    ; DWMWA_CAPTION_COLOR
            NumPut("UInt", Look.ColorRef(Look.HAZE), value)
            DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 36, "Ptr", value, "UInt", 4)    ; DWMWA_TEXT_COLOR
        }
        icon := A_ScriptDir "\assets\synseeder.ico"
        if !A_IsCompiled && FileExist(icon) {
            for item in [[0, 49], [1, 11]] {  ; ICON_SMALL at SM_CXSMICON, ICON_BIG at SM_CXICON
                size := DllCall("GetSystemMetrics", "Int", item[2], "Int")
                try SendMessage(0x80, item[1], LoadPicture(icon, "Icon1 w" size " h" size, &kind), hwnd)  ; WM_SETICON
            }
        }
    }

    ShowClock() {
        h := Integer(this.hour)
        this.clock.Text := (Mod(h, 12) || 12) ":" this.minute " " (h < 12 ? "AM" : "PM")
    }

    ; The pinged hours in AM and PM beside their pickers.
    ShowPingHours() {
        ampm(hour) => (Mod(Integer(hour), 12) || 12) " " (hour < 12 ? "AM" : "PM")
        this.pingClock.Text := this.pingFrom = this.pingUntil ? "All day"
            : ampm(this.pingFrom) " " Chr(0x2013) " " ampm(this.pingUntil)
    }

    ; The hour of "HH:MM" as two digits, read as the check reads it, or
    ; ``default`` if it isn't a time.
    static _Hour(time, default) => Format("{:02d}", SeedCalls.MinuteOfDay(time, default * 60) // 60)

    ; ``time`` as it is if it's a time in ``hour``, so minutes set by hand in
    ; the settings file are kept; else ``hour`` ":00".
    static _Time(time, hour) => SeedCalls.MinuteOfDay(time, -60) // 60 = hour ? time : hour ":00"

    ; Shows the player count, or ``note`` when it isn't known ("").
    ShowServer(count, note := "") {
        this.count := count
        this.note := note != "" ? note : SetupWindow.UNREACHABLE
        Skin.Redraw(this.players.Hwnd)
    }

    ; What the line under the count says on the right.
    NeedText() {
        if this.count = ""
            return ""
        missing := this.config.seeded_threshold - this.count
        return missing > 0 ? "Needs " missing " more" : "Seeded"
    }

    Status(text, rgb := Look.MIST) {
        this._FitStatus(text)
        this.statusLine.SetFont("c" Look.Hex(rgb))
        this.statusLine.Text := text
        this.statusColor := rgb
    }

    ; Makes the status line as tall as ``text`` needs (two lines at least),
    ; moving what's below it and growing or shrinking the window to match.
    _FitStatus(text) {
        need := Max(this.statusMinH, SetupWindow.TextHeight(this.statusLine, text, this.statusW))
        delta := need - this.statusH
        if !delta
            return
        this.statusLine.GetPos(, &top)
        for hwnd, ctrl in this.gui {
            ctrl.GetPos(, &y)
            if y > top
                ctrl.Move(, y + delta)
        }
        this.statusLine.Move(, , , need)
        this.statusH := need, this.height += delta
        this._FitWindow()
    }

    ; Makes the window this.height tall inside. Not while it's hidden (Show
    ; sizes it) or minimized: there Windows would size the minimized window and
    ; restore the old size, so the Size event does it once it's restored.
    _FitWindow() {
        hwnd := this.gui.Hwnd
        if !DllCall("IsWindowVisible", "Ptr", hwnd) || DllCall("IsIconic", "Ptr", hwnd)
            return
        rect := Buffer(16, 0)
        DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rect)
        if (inner := NumGet(rect, 12, "Int")) != this.height {
            this.gui.GetPos(, , , &outer)
            this.gui.Move(, , , outer + this.height - inner)
        }
    }

    ; How tall ``text`` is in ``ctrl``'s font, wrapped at ``width`` pixels.
    static TextHeight(ctrl, text, width) {
        if text = ""
            return 0
        dc := DllCall("GetDC", "Ptr", ctrl.Hwnd, "Ptr")
        old := DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", SendMessage(0x31, 0, 0, ctrl), "Ptr")  ; WM_GETFONT
        rect := Buffer(16, 0)
        NumPut("Int", width, rect, 8)
        DllCall("DrawTextW", "Ptr", dc, "Str", text, "Int", -1, "Ptr", rect, "UInt", 0xC11)  ; DT_CALCRECT | DT_NOPREFIX | DT_WORDBREAK | DT_CENTER
        DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", old)
        DllCall("ReleaseDC", "Ptr", ctrl.Hwnd, "Ptr", dc)
        return NumGet(rect, 12, "Int")
    }

    ; What the window does

    ScheduleText() {
        daily := DailyTask.IsScheduled()
        pinged := SeedCalls.On(this.config) && DailyTask.CallsScheduled()
        if pinged {
            from := SeedCalls.MinuteOfDay(this.config.pinged_from, 8 * 60), upTo := SeedCalls.MinuteOfDay(this.config.pinged_until, 23 * 60)
            hours := from = upTo ? "at any hour" : Format("from {:02d}:{:02d} to {:02d}:{:02d}", from // 60, Mod(from, 60), upTo // 60, Mod(upTo, 60))
        }
        if daily && pinged
            return "Seeds every day at " this.config.start_time ", and when pinged " hours ". Leave the PC on, signed in and unlocked; if it's asleep at " this.config.start_time ", it runs when it wakes."
        if daily
            return "Seeds every day at " this.config.start_time ". Leave the PC on, signed in and unlocked; if it's asleep it runs when it wakes."
        if pinged
            return "Seeds when pinged on Discord, " hours ". Leave the PC on, signed in and unlocked."
        return "Not scheduled. Tick " Chr(0x201C) "Seed automatically" Chr(0x201D) " or " Chr(0x201C) "Seed when pinged" Chr(0x201D) " and Save."
    }

    ; Fetches the player count without holding up the window. One fetch at a
    ; time, so a slow one can't land after a newer count and replace it.
    RefreshServer() {
        if this.request != ""
            return
        try {
            this.request := Http.Start(this.config.crcon_url, "application/json", SetupWindow.SERVER_TIMEOUT_MS / 1000, true)
            this.requestAt := A_TickCount
            SetTimer(this.pollTimer, 100)
        } catch as err {
            this.request := ""
            Logs.Warning("Could not read server status from " this.config.crcon_url ": " err.Message)
            this.ShowServer("")
        }
    }

    PollServer() {
        req := this.request
        if req = "" {
            SetTimer(this.pollTimer, 0)
            return
        }
        try {
            if !Http.Done(req) {
                if A_TickCount - this.requestAt < SetupWindow.SERVER_TIMEOUT_MS
                    return
                try req.Abort()
                throw Error("no answer in " SetupWindow.SERVER_TIMEOUT_MS // 1000 " seconds")
            }
            count := ServerStats.Read(Http.BodyText(Http.Check(req))).players
        } catch as err {
            Logs.Warning("Could not read server status from " this.config.crcon_url ": " err.Message)
            count := ""
        }
        SetTimer(this.pollTimer, 0)
        this.request := ""
        this.ShowServer(count)
    }

    ; Keeps the status line true when a run starts or ends outside the buttons:
    ; Ctrl+Alt+End, the schedule, the server filling up, or the time limit.
    WatchSeed() {
        if this.busy
            return
        running := SeedLock.Running() || (this.spawned && SeedLock.Alive(this.spawned))
        if !running
            this.spawned := 0
        this.ShowSeeding(running)
    }

    ShowSeeding(running) {
        if running == this.seeding
            return
        was := this.seeding
        this.seeding := running
        if running
            this.Status("Seeding now. Ctrl+Alt+End or Stop seeding ends it.")
        else if was == true
            this.Status("The run has ended.")
    }

    ; Saves the settings and creates or removes the daily and seed-calls
    ; tasks. False if any of that failed.
    Save(*) {
        this.config.start_time := this.hour ":" this.minute
        this.config.launcher := this.launcher
        this.config.seed_when_pinged := this.pinged ? true : false
        this.config.pinged_from := SetupWindow._Time(this.config.pinged_from, this.pingFrom)
        this.config.pinged_until := SetupWindow._Time(this.config.pinged_until, this.pingUntil)
        problem := ""
        try {
            this.config.Save()
            if this.enabled
                DailyTask.Schedule(this.config.start_time)
            else
                DailyTask.Unschedule()
        } catch as err {
            Logs.Exception("Scheduling failed", err)
            problem := "Couldn't set up the schedule: " err.Message
        }
        ; Done even if the above failed: unticked, the task must go whatever
        ; the settings file says (a check reads that file, so it's off anyway).
        try {
            if this.pinged
                DailyTask.ScheduleCalls()
            else
                DailyTask.UnscheduleCalls()
        } catch as err {
            Logs.Exception("Setting up Seed when pinged failed", err)
            if problem = ""
                problem := "Couldn't set up Seed when pinged: " err.Message
        }
        if problem != "" {
            this.Status(problem, Look.FLARE)
            return false
        }
        this.Status("Saved. " this.ScheduleText())
        return true
    }

    ; A Stop seeding click waits until this has started the run, so it can
    ; stop it: Critical holds other clicks back until it returns.
    SeedNow(*) {
        was := A_IsCritical
        Critical
        try
            this._SeedNow()
        finally
            Critical(was)  ; (a test calls it from its own thread)
    }

    _SeedNow() {
        if this.busy
            return
        if SeedLock.Running() || (this.spawned && SeedLock.Alive(this.spawned)) {
            if this.Save()  ; Seed now saves the settings whatever happens (TERMS.md)
                this.Status("Saved. Already seeding.")
            return
        }
        this.Save()
        ; A run stops at once in these cases, so say why here rather than "started".
        if this.count != "" && this.count >= this.config.seeded_threshold {
            this.Status("The server is already seeded (" this.count " players), so there's nothing to do.")
            return
        }
        if HllGame(this.config).Running() {
            this.Status("The game is already open. Close it first: Seed now won't take over a game you're playing.")
            return
        }
        try {
            this.spawned := this.StartRun()
        } catch as err {
            Logs.Exception("Couldn't start seeding", err)
            this.Status("Couldn't start seeding: " err.Message, Look.FLARE)
            return
        }
        this.StopLateWatch()  ; the game is this run's to open now
        this.seeding := true
        this.Status("Seeding started. The game will open shortly; leave the mouse and keyboard alone while it joins.")
    }

    ; Starts a seeding run in its own process. Returns its process ID.
    StartRun() {
        command := DailyTask.SeedCommand()
        return SeedLock.Spawn(command[1], command[2])
    }

    StopSeeding(*) {
        if this.busy
            return
        this.busy := true
        spawned := this.spawned
        this.seeding := false, this.spawned := 0
        this.Status("Stopping...")
        try {
            ended := {forced: false}
            if this.EndRuns(spawned, ended) {
                HllGame(this.config).Close()
                if ended.forced {
                    ; It may have been waiting for the launcher to start the game.
                    this.WatchLateGame(HllGame.LATE_START_SECONDS - SetupWindow.STOP_WAIT)
                    this.Status("Stopped seeding and closed the game. If the launcher still starts the game "
                        . "in the next minute, it's closed too.")
                } else {
                    this.Status("Stopped seeding and closed the game.")
                }
            } else {
                this.Status("Nothing is seeding right now.")
            }
        } catch as err {
            Logs.Exception("Stopping failed", err)
            this.Status("Couldn't stop seeding: " err.Message, Look.FLARE)
        } finally {
            this.busy := false
        }
    }

    ; Asks every run to stop (it closes the game and ends), and ends any that
    ; haven't within STOP_WAIT seconds. Looks again after each round, in case a
    ; run was handing over to a new version. ``spawned`` is a run Seed now
    ; started that may not have named its window yet. True if there was a run;
    ; ``ended.forced`` says if one had to be ended.
    EndRuns(spawned := 0, ended := "") {
        found := false, passes := 0
        while passes < 3 {
            pids := this._AskRuns(spawned)
            spawned := 0
            ; A run holds the lock a moment before it names its window (a new
            ; version taking over, for one): give it a few seconds to.
            grace := A_TickCount + 5000
            while !pids.Length && SeedLock.HeldElsewhere() && A_TickCount < grace {
                Sleep(250)
                pids := this._AskRuns(0)
            }
            if !pids.Length
                break
            found := true, passes++
            for pid in pids
                if pid && !SeedLock.WaitEnd(pid, SetupWindow.STOP_WAIT) {
                    Logs.Warning("Run " pid " didn't stop by itself; ending it")
                    SeedLock.End(pid)
                    if IsObject(ended)
                        ended.forced := true
                }
        }
        ; A new version a run was handing over to, not far enough along to
        ; be asked (SynSeeder-update.exe only ever runs as one).
        tried := Map()
        while (pid := SeedLock.Find(Updater.UPDATE_NAME)) && !tried.Has(pid) {
            tried[pid] := true
            found := true
            Logs.Warning("Ending " Updater.UPDATE_NAME " (" pid "), which was taking over a run")
            SeedLock.End(pid)
            SeedLock.WaitEnd(pid, 5)
        }
        if found
            Logs.Info("Stopped seeding from the window")
        return found
    }

    ; Asks every run with its window up to stop. Returns their process IDs.
    ; ``spawned``, a run Seed now started, is asked too once its window is up
    ; (within START_GRACE_MS of starting); if it doesn't get that far, it's
    ; ended there and then, before it can start seeding (a run names its
    ; window before it does anything else), and is in the list too.
    _AskRuns(spawned) {
        pids := []
        for hwnd in SeedLock.Runs()
            pids.Push(SeedLock.Ask(hwnd))
        if !spawned || SetupWindow._Has(pids, spawned) || !SeedLock.Alive(spawned)
            return pids
        endAt := A_TickCount + SetupWindow.START_GRACE_MS
        loop {
            Sleep(100)
            for hwnd in SeedLock.Runs() {
                if SeedLock.Owner(hwnd) = spawned {
                    pids.Push(SeedLock.Ask(hwnd))
                    return pids
                }
            }
            if !SeedLock.Alive(spawned)
                return pids
            if A_TickCount >= endAt
                break
        }
        Logs.Info("Ending the run Seed now started before it got going")
        SeedLock.End(spawned)
        pids.Push(spawned)
        return pids
    }

    ; For ``seconds`` after a stop that had to end a run, closes the game if
    ; the launcher still starts it. A new run (Seed now, the schedule, another
    ; window) owns the game, so it ends the watch.
    WatchLateGame(seconds) {
        this.StopLateWatch()
        endAt := A_TickCount + seconds * 1000
        check() {
            if SeedLock.Running() {
                this.StopLateWatch()
                return
            }
            if pid := HllGame(this.config).Pid() {
                HllGame._End(pid)
                this.StopLateWatch()
                return
            }
            if A_TickCount >= endAt
                this.StopLateWatch()
        }
        this.lateWatch := check
        SetTimer(check, 2000)
    }

    StopLateWatch() {
        if this.lateWatch
            SetTimer(this.lateWatch, 0)
        this.lateWatch := ""
        if this.exitAfterWatch
            this.Exit()
    }

    ChooseLauncher(which) {
        this.launcher := which
        Skin.Redraw(this.steamChip.Hwnd), Skin.Redraw(this.epicChip.Hwnd)
    }

    ToggleAutomatic(*) {
        this.enabled := !this.enabled
        Skin.Redraw(this.autoBox.Hwnd)
    }

    TogglePinged(*) {
        this.pinged := !this.pinged
        Skin.Redraw(this.pingBox.Hwnd)
    }

    OpenLog(*) {
        path := Logs.path != "" ? Logs.path : App.Dir "\seeder.log"
        if !FileExist(path)
            return
        try
            Run(QuoteArg(path))
        catch
            try Run("notepad.exe " QuoteArg(path))
    }

    Open(url) {
        try Run(url)
    }

    ; Closing the window ends SynSeeder, unless it's watching for a late game:
    ; then the window goes, and SynSeeder ends when the watch does.
    Close() {
        this.ClosePicker()
        if this.lateWatch {
            this.exitAfterWatch := true
            this.gui.Hide()
            return
        }
        this.Exit()
    }

    Exit() => ExitApp(0)

    ; Stops the timers and closes the window without exiting (tests).
    Dispose() {
        SetTimer(this.pollTimer, 0)
        this.exitAfterWatch := false
        this.StopLateWatch()
        this.ClosePicker()
        for ctrl in this.gui
            Skin.Forget(ctrl)
        this.gui.Destroy()
    }

    ; The hour and minute grids

    ; The picker for ``which``: "hour", "minute", "pingFrom" or "pingUntil",
    ; the window's properties holding their values.
    _Field(which) => which = "hour" ? this.hourField : which = "minute" ? this.minuteField
        : which = "pingFrom" ? this.pingFromField : this.pingUntilField

    ; Opens the grid of hours or minutes under the picker for ``which``.
    OpenPicker(which) {
        if this.picker != "" {
            same := this.picker.which = which
            this.ClosePicker()
            if same
                return
        }
        if this.pickerClosed[1] = which && A_TickCount - this.pickerClosed[2] < 400
            return  ; the click on this picker is what closed its grid
        px(n) => Look.Px(n)
        f := this.fonts
        values := which = "minute" ? SetupWindow.MINUTES : SetupWindow.HOURS
        columns := which = "minute" ? 4 : 6
        cell := {w: px(44), h: px(30)}
        inset := px(4), w := 2 * inset + columns * cell.w, h := 2 * inset + Ceil(values.Length / columns) * cell.h
        field := this._Field(which)
        chosen := SetupWindow._Index(values, this.%which%)
        pop := Gui("-Caption +ToolWindow -DPIScale +Owner" this.gui.Hwnd)
        pop.BackColor := Look.Hex(Look.SLATE)
        pop.MarginX := 0, pop.MarginY := 0
        grid := pop.Add("Text", "x0 y0 w" w " h" h " +0xD +0x100")  ; owner-drawn, and told about clicks
        state := this.picker := {which: which, gui: pop, grid: grid, values: values, columns: columns, cell: cell
            , inset: inset, chosen: chosen, hot: chosen, field: field}
        Skin.Add(grid, (c, st) => Paint.Grid(c, values, columns, cell, f.body, state.chosen, state.hot))
        grid.OnEvent("Click", (*) => this._GridClick())
        ; under the picker, right edges lined up; above it if there's no room below
        field.GetPos(&fx, &fy, &fw, &fh)
        WinGetClientPos(&cx, &cy, , , this.gui)
        x := cx + fx + fw - w, y := cy + fy + fh + px(4)
        area := SetupWindow.WorkAreaAt(cx + fx, cy + fy, cx + fx + fw, cy + fy + fh)
        if y + h > area.bottom
            y := cy + fy - px(4) - h >= area.top ? cy + fy - px(4) - h : Max(area.top, area.bottom - h)
        x := Max(area.left, Min(x, area.right - w))
        pop.Show("x" x " y" y " w" w " h" h)
    }

    ; Closes the open grid; ``refocus`` puts the keyboard back on its picker.
    ClosePicker(refocus := false) {
        state := this.picker
        if state = ""
            return
        this.picker := ""
        Skin.Forget(state.grid)
        try state.gui.Destroy()
        if refocus
            try ControlFocus(state.field)
    }

    ; Sets the open grid's hour or minute to its value number ``index``.
    Pick(index) {
        state := this.picker
        if state = "" || index < 1 || index > state.values.Length
            return
        value := state.values[index]
        this.%state.which% := value, state.field.Text := value
        this.ClosePicker(true)
        Skin.Redraw(state.field.Hwnd)
        this.ShowClock(), this.ShowPingHours()
    }

    ; The grid's value number under (x, y) in the grid, or 0.
    _CellAt(x, y) {
        state := this.picker
        col := Floor((x - state.inset) / state.cell.w), row := Floor((y - state.inset) / state.cell.h)
        if col < 0 || col >= state.columns || row < 0
            return 0
        index := row * state.columns + col + 1
        return index <= state.values.Length ? index : 0
    }

    _GridClick() {
        state := this.picker
        if state = ""
            return
        point := Buffer(8, 0)
        DllCall("GetCursorPos", "Ptr", point)
        DllCall("ScreenToClient", "Ptr", state.grid.Hwnd, "Ptr", point)
        this.Pick(this._CellAt(NumGet(point, 0, "Int"), NumGet(point, 4, "Int")))
    }

    _GridMove(wParam, lParam, msg, hwnd) {
        state := this.picker
        if state = "" || hwnd != state.grid.Hwnd
            return
        index := this._CellAt(lParam << 48 >> 48, lParam << 32 >> 48)
        if index && index != state.hot {
            state.hot := index
            Skin.Redraw(state.grid.Hwnd)
        }
    }

    ; Arrow keys move round the grid, Enter or Space picks, Esc or Tab closes it.
    _Key(wParam, lParam, msg, hwnd) {
        state := this.picker
        if state = "" || DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") != state.gui.Hwnd  ; GA_ROOT
            return
        n := state.values.Length, c := state.columns, hot := state.hot ? state.hot : 1
        switch wParam {
            case 0x25: hot := Max(1, hot - 1)                      ; left
            case 0x27: hot := Min(n, hot + 1)                      ; right
            case 0x26: hot := hot - c >= 1 ? hot - c : hot         ; up
            case 0x28: hot := hot + c <= n ? hot + c : hot         ; down
            case 0x0D, 0x20:
                this.Pick(hot)
                return 0
            case 0x1B, 0x09:
                this.ClosePicker(true)
                return 0
            default:
                return
        }
        state.hot := hot
        Skin.Redraw(state.grid.Hwnd)
        return 0
    }

    ; Clicking anywhere else closes the grid.
    _Activate(wParam, lParam, msg, hwnd) {
        state := this.picker
        if state != "" && hwnd = state.gui.Hwnd && !(wParam & 0xFFFF)  ; WA_INACTIVE
            SetTimer(ObjBindMethod(this, "_ClickedAway", state), -1)
    }

    ; If the click that closed the grid was on its own picker, OpenPicker then
    ; knows not to open it again.
    _ClickedAway(state) {
        if this.picker != state
            return
        this.ClosePicker()
        this.pickerClosed := [state.which, A_TickCount]
    }

    static _Index(list, value) {
        for item in list
            if item == value
                return A_Index
        return 0
    }

    static _Has(list, value) => SetupWindow._Index(list, value) > 0
}
