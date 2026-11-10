; Opens the setup window, puts it in a given state and saves a picture of
; it, to check the look (CI keeps the pictures). Nothing is saved or scheduled.
; Exits with 3 if the seedling isn't whole: in a new process, as here, the
; window is the first thing SynSeeder draws.
;
;   AutoHotkey64.exe tests\window_shot.ahk OUT.png [players, or none] [grid]
#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
#Warn LocalSameAsGlobal, Off
#Include ..\src\Build.ahk
#Include ..\src\App.ahk
#Include ..\src\Json.ahk
#Include ..\src\Config.ahk
#Include ..\src\Http.ahk
#Include ..\src\Gdip.ahk
#Include ..\src\Vision.ahk
#Include ..\src\ButtonFiles.ahk
#Include ..\src\Buttons.ahk
#Include ..\src\WinApi.ahk
#Include ..\src\GameScreen.ahk
#Include ..\src\Flow.ahk
#Include ..\src\HllGame.ahk
#Include ..\src\Runner.ahk
#Include ..\src\SeedLock.ahk
#Include ..\src\DailyTask.ahk
#Include ..\src\SeedCalls.ahk
#Include ..\src\Updater.ahk
#Include ..\src\FontFiles.ahk
#Include ..\src\Look.ahk
#Include ..\src\SetupWindow.ahk
#Include Seedling.ahk

OnError(Crashed)
Crashed(err, mode) {
    FileAppend("CRASH: " Type(err) ": " err.Message "`n" err.Stack "`n", "*", "UTF-8")
    ExitApp(2)
}

out := A_Args.Length ? StartPath(A_Args[1]) : A_Temp "\window.png"
players := A_Args.Length >= 2 ? A_Args[2] : "37"
App.dirOverride := A_Temp "\synseeder-shot"
Logs.echo := true
config := SeederConfig()
w := SetupWindow(config, false)
w.Show()
w.ShowServer(players = "none" ? "" : Integer(players))
if A_Args.Length >= 3 && A_Args[3] = "grid"
    w.OpenPicker("hour")
Sleep(800)
g := w.gui
WinGetClientPos(&x, &y, &cw, &ch, g)
h := ch
if w.picker != "" {
    WinGetPos(&px, &py, &pw, &ph, w.picker.gui)
    h := Max(ch, py + ph - y)
}
shot := Canvas(cw, h, 0)
screen := DllCall("GetDC", "Ptr", 0, "Ptr")
DllCall("BitBlt", "Ptr", shot.dc, "Int", 0, "Int", 0, "Int", cw, "Int", h, "Ptr", screen, "Int", x, "Int", y, "UInt", 0x40CC0020)
DllCall("ReleaseDC", "Ptr", 0, "Ptr", screen)
shot.Save(out)
FileAppend("saved " out " (" cw "x" ch ", fonts " w.fonts.body.actualFace " / " w.fonts.title.actualFace ")`n", "*", "UTF-8")
problems := SeedlingCheck.Problems(w.header)
if problems.Length {
    FileAppend("FAIL: " JoinList(problems, "; ") "`n", "*", "UTF-8")
    ExitApp(3)
}
ExitApp(0)
