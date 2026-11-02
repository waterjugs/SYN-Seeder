; "SynSeeder.exe --selftest LOG" checks, on a real Windows PC without the
; game, the parts the other tests can't: Windows' own screen shrinking, the
; daily task, the button image and font downloads, and that the exe starts.
; CI runs it on every build. Lines are PASS or FAIL checks, or notes.

class SelfTest {
    static Run(logPath) {
        logPath := StartPath(logPath)
        lines := [], ok := true
        check(name, pass, detail := "") {
            lines.Push((pass ? "PASS " : "FAIL ") name (detail != "" ? " (" detail ")" : ""))
            if !pass
                ok := false
        }
        note(name, detail) => lines.Push("     " name ": " detail)

        note("SynSeeder", "v" App.VERSION (Build.RELEASE ? " release" : " test build")
            . (Build.COMMIT != "" ? " of " Build.COMMIT : "") (A_IsCompiled ? "" : " (script)"))
        Logs.Open(A_Temp "\SynSeeder-selftest.log")
        steps := [
            ["version", () => check("version number " App.VERSION, App.ParseVersion(App.VERSION) != "")],
            ["settings", () => SelfTest.Settings(check)],
            ["task XML", () => SelfTest.TaskXml(check)],
            ["daily task", () => SelfTest.Task(check)],
            ["shrinking", () => SelfTest.Shrinking(check, note)],
            ["button images", () => SelfTest.ButtonImages(check, note)],
            ["fonts", () => SelfTest.Fonts(check)],
            ["screen", () => SelfTest.Screen(note)],
            ["server", () => SelfTest.Server(note)],
            ["release", () => SelfTest.Release(note)]]
        for step in steps {
            try {
                step[2]()
            } catch as err {
                check(step[1], false, Type(err) ": " err.Message " at line " err.Line)
            }
        }
        lines.Push(ok ? "SELFTEST OK" : "SELFTEST FAILED")
        text := JoinList(lines, "`n") "`n"
        try FileDelete(logPath)
        FileAppend(text, logPath, "UTF-8")
        return ok ? 0 : 1
    }

    static Settings(check) {
        path := A_Temp "\SynSeeder-selftest-config.json"
        config := SeederConfig()
        config.start_time := "06:45", config.launcher := "epic", config.auto_update := false
        config.Save(path)
        again := SeederConfig.Load(path)
        text := FileRead(path, "UTF-8")
        FileDelete(path)
        check("settings save and load", again.start_time = "06:45" && again.launcher = "epic" && !again.auto_update
            && again.seeded_threshold = 80 && InStr(text, '"auto_update": false'))
    }

    static TaskXml(check) {
        xml := DailyTask.Xml("07:30", "C:\A & B\SynSeeder.exe", "--seed", "20261102080000")
        check("daily task XML", InStr(xml, "<Command>C:\A &amp; B\SynSeeder.exe</Command>")
            && InStr(xml, "<StartBoundary>2026-11-03T07:30:00</StartBoundary>")
            && InStr(xml, "<Arguments>--seed</Arguments>"))
    }

    ; Registers, finds and deletes a task under another name; the player's own task isn't touched.
    static Task(check) {
        name := DailyTask.NAME " selftest"
        xml := DailyTask.Xml("03:15", A_WinDir "\System32\rundll32.exe", "--seed")
        DailyTask.Register(name, xml)
        found := DailyTask.Exists(name)
        DailyTask.Delete(name)
        check("daily task registers and deletes", found && !DailyTask.Exists(name))
    }

    ; The button finder expects each working pixel to be the rounded average of
    ; an f x f block of screen pixels, as its screenshot cases are made
    ; (GameScreen.Shrink).
    static Shrinking(check, note) {
        for f in [2, 3, 4] {
            result := SelfTest.ShrinkError(96, 60, f)
            check("screen shrink by " f " averages blocks", result.max <= 2,
                "largest difference " result.max ", average " Round(result.mean, 3) ", by " result.how)
        }
        ; How long a big screen takes: 5120x2160 shrinks by 3.
        src := GameScreen._MakeDib(5120, 2160)
        dst := GameScreen._MakeDib(5120 // 3, 2160 // 3)
        try {
            DllCall("QueryPerformanceFrequency", "Int64*", &freq := 0)
            DllCall("QueryPerformanceCounter", "Int64*", &t0 := 0)
            how := GameScreen.Shrink(src, dst, 3)
            DllCall("QueryPerformanceCounter", "Int64*", &t1 := 0)
            note("shrinking 5120x2160", Round((t1 - t0) * 1000 / freq) " ms, by " how)
        } finally {
            GameScreen._FreeDibOf(src)
            GameScreen._FreeDibOf(dst)
        }
    }

    ; How far the app's shrink strays from block averages on a w x h test pattern.
    static ShrinkError(w, h, f) {
        src := GameScreen._MakeDib(w, h)
        dst := GameScreen._MakeDib(w // f, h // f)
        try {
            seed := 12345
            loop w * h {  ; noisy pattern with some smooth areas, like a game screen
                seed := Mod(seed * 1103515245 + 12345, 0x80000000)
                i := A_Index - 1, x := Mod(i, w), y := i // w
                base := (x * 255 // w) | ((y * 255 // h) << 8) | (((x + y) * 3 & 255) << 16)
                pixel := (y // 12) & 1 ? (seed >> 8) & 0xFFFFFF : base
                NumPut("UInt", pixel, src.bits, i * 4)
            }
            how := GameScreen.Shrink(src, dst, f)
            worst := 0, total := 0, count := 0
            loop h // f {
                by := A_Index - 1
                loop w // f {
                    bx := A_Index - 1
                    got := NumGet(dst.bits, (by * (w // f) + bx) * 4, "UInt")
                    loop 3 {
                        shift := (A_Index - 1) * 8, sum := 0
                        loop f {
                            yy := by * f + A_Index - 1
                            loop f
                                sum += NumGet(src.bits, (yy * w + bx * f + A_Index - 1) * 4, "UInt") >> shift & 255
                        }
                        want := (sum + f * f // 2) // (f * f)
                        diff := Abs((got >> shift & 255) - want)
                        worst := Max(worst, diff), total += diff, count++
                    }
                }
            }
            return {max: worst, mean: total / count, how: how}
        } finally {
            GameScreen._FreeDibOf(src)
            GameScreen._FreeDibOf(dst)
        }
    }

    static ButtonImages(check, note) {
        crops := LoadButtons()
        count := 0
        for name, list in crops
            count += list.Length
        check("button images", !Buttons.Missing(crops).Length, count " images")
        if A_IsCompiled {
            bad := []
            for fileName, sha in ButtonFiles.SHA256
                if Sha256.File(Buttons.Folder "\" fileName) != sha
                    bad.Push(fileName)
            check("downloaded button images match", !bad.Length, JoinList(bad))
        }
    }

    ; The window's fonts: downloaded and checked like the button images in a
    ; built exe, and usable once loaded.
    static Fonts(check) {
        loaded := Look.LoadFonts()
        check("fonts", loaded = FontFiles.SHA256.Count, loaded " of " FontFiles.SHA256.Count " loaded")
        for face in ["Inter", "Barlow Condensed SemiBold"]
            check("font " face, Font(face, 10).actualFace = face)
    }

    static Screen(note) {
        screen := GameScreen(Map())
        screen.Refresh()
        note("screen", screen.area.w "x" screen.area.h " at " screen.area.left "," screen.area.top
            . ", shrunk by " Vision.Factor(screen.area.h) (screen.blackTicks ? ", black" : ""))
        note("idle", Round(WinApi.UserIdleSeconds(), 1) " s; desktop " (WinApi.DesktopUnlocked() ? "unlocked" : "locked"))
    }

    static Server(note) {
        status := ServerStats.Fetch(SeederConfig().crcon_url)
        note("server", status ? status.name ": " status.players " players (" status.allied " v " status.axis ")" : "unreachable")
    }

    static Release(note) {
        release := Updater.Latest()
        note("latest release", release ? release.tag : "none")
    }
}
