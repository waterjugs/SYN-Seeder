; Checks the button finder on the screenshot cases tests/make_fixtures.py builds.
;
;   AutoHotkey64.exe /ErrorStdOut tests\vision_cases.ahk build\fixtures [templates] [scores.json]
;
; Prints a line per case and exits with 0 if every case passed. With a third
; argument, also writes every button's best score on every case to that file.
#Requires AutoHotkey v2.0
#NoTrayIcon
#Warn All, StdOut
#Warn LocalSameAsGlobal, Off
#Include ..\src\Build.ahk
#Include ..\src\App.ahk
#Include ..\src\Json.ahk
#Include ..\src\Http.ahk
#Include ..\src\Gdip.ahk
#Include ..\src\Vision.ahk
#Include ..\src\Buttons.ahk

OVERLAYS := ["admin_yes", "game_menu_leave"]
SCREENS := ["admin_yes", "game_menu_leave", "deploy_button", "roles_confirm", "select_force", "create_unit",
    "switch_team", "server_row", "browser_search", "browser_refresh", "menu_enlist"]

Say(text) => FileAppend(text "`n", "*", "UTF-8")

; Print errors instead of showing a dialog nobody can click.
OnError(Crashed)
Crashed(err, mode) {
    Say("ERROR: " err.Message (err.Extra != "" ? " (" err.Extra ")" : "") "`n" err.Stack)
    ExitApp 2
}

CurrentScreen(finder) {
    for name in SCREENS
        if finder.Find(name)
            return name
    return ""
}

Within(value, range) => range[1] <= value && value <= range[2]

RunCheck(finder, crops, check, frame) {
    if check.Has("find") {
        name := check["find"]
        region := check.Has("region") ? check["region"] : ""
        pos := finder.Find(name, region)
        if check.Has("missing")
            return pos ? name " found at " pos[1] "," pos[2] " but shouldn't be" : ""
        if !pos
            return name " not found"
        if check.Has("x") && !Within(pos[1], check["x"])
            return name " x " pos[1] " outside " Round(check["x"][1], 1) "-" Round(check["x"][2], 1)
        if check.Has("y") && !Within(pos[2], check["y"])
            return name " y " pos[2] " outside " Round(check["y"][1], 1) "-" Round(check["y"][2], 1)
        return ""
    }
    if check.Has("join_on_row") {
        row := finder.Find("server_row")
        joins := finder.FindAll("browser_join")
        if !row || !joins.Length
            return "server row " (row ? "found" : "missing") ", " joins.Length " JOIN buttons"
        join := joins[1]
        for j in joins
            if Abs(j[2] - row[2]) < Abs(join[2] - row[2])
                join := j
        if check.Has("row_x") && !Within(row[1], check["row_x"])
            return "row x " row[1]
        if check.Has("row_y") && !Within(row[2], check["row_y"])
            return "row y " row[2]
        if check.Has("x") && !Within(join[1], check["x"])
            return "JOIN x " join[1] " outside " Round(check["x"][1], 1) "-" Round(check["x"][2], 1)
        if check.Has("y") && !Within(join[2], check["y"])
            return "JOIN y " join[2] " outside " Round(check["y"][1], 1) "-" Round(check["y"][2], 1)
        if check.Has("row_dy") && Abs(join[2] - row[2]) >= check["row_dy"]
            return "JOIN " join[2] " not level with the row " row[2]
        return ""
    }
    if check.Has("only_cut") {
        name := check["name"], only := Map()
        for key, list in crops
            only[key] := list
        only[name] := []
        for crop in crops[name]
            if crop.cut = check["only_cut"]
                only[name].Push(crop)
        if !only[name].Length
            return "no " name "." check["only_cut"] "p.png"
        alone := Vision(only)
        alone.SetFrame(frame.buf.Ptr, frame.w, frame.h, frame.stride, finder.W, finder.H, finder.f)
        return alone.Find(name) ? "" : name "." check["only_cut"] "p.png alone doesn't find it"
    }
    if check.Has("count") {
        n := finder.FindAll(check["count"]).Length
        return n >= check["min"] ? "" : check["count"] " found " n " times, wanted " check["min"]
    }
    return "unknown check"
}

Main() {
    folder := A_Args.Length >= 1 ? StartPath(A_Args[1]) : A_ScriptDir "\..\build\fixtures"
    templates := A_Args.Length >= 2 ? StartPath(A_Args[2]) : A_ScriptDir "\..\templates"
    scoresFile := A_Args.Length >= 3 ? StartPath(A_Args[3]) : ""
    crops := Buttons.Load(templates)
    missing := Buttons.Missing(crops)
    if missing.Length {
        Say("Missing button images: " Json.Dump(missing))
        ExitApp 1
    }
    cases := Json.Load(FileRead(folder "\cases.json", "UTF-8"))
    failed := 0, slowest := 0, total := 0, scores := Map()
    DllCall("QueryPerformanceFrequency", "Int64*", &freq := 0)
    for item in cases {
        frame := Gdip.LoadBits(folder "\" StrReplace(item["file"], "/", "\"))
        finder := Vision(crops)
        finder.SetFrame(frame.buf.Ptr, frame.w, frame.h, frame.stride, item["width"], item["height"], item["factor"])
        CurrentScreen(finder)  ; the first look also prepares the button images; time the next
        DllCall("QueryPerformanceCounter", "Int64*", &t0 := 0)
        screen := CurrentScreen(finder)
        DllCall("QueryPerformanceCounter", "Int64*", &t1 := 0)
        ms := (t1 - t0) * 1000 / freq
        total += ms, slowest := Max(slowest, ms)
        problems := []
        want := item["screen"]
        if screen != want
            problems.Push("saw " (screen = "" ? "nothing" : screen) ", expected " (want = "" ? "nothing" : want))
        for check in item["checks"] {
            problem := RunCheck(finder, crops, check, frame)
            if problem != ""
                problems.Push(problem)
        }
        if scoresFile != "" {
            row := Map()
            for name in Vision.REQUIRED
                row[name] := Round(finder.BestScore(name), 6)
            scores[item["label"]] := row
        }
        line := Format("{:-5} {:-28} {:5.0f} ms  {}", problems.Length ? "FAIL" : "ok", item["label"], ms, screen = "" ? "-" : screen)
        for problem in problems
            line .= "`n      " problem
        Say(line)
        failed += problems.Length ? 1 : 0
    }
    if scoresFile != ""
        FileOpen(scoresFile, "w", "UTF-8-RAW").Write(Json.Dump(scores, " "))
    Say(Format("{} of {} cases passed; screen check {:.0f} ms on average, {:.0f} ms at most",
        cases.Length - failed, cases.Length, total / cases.Length, slowest))
    ExitApp failed ? 1 : 0
}

Main()
