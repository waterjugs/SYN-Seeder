; SynSeeder's tests. Run with AutoHotkey 2.0.18:
;
;   AutoHotkey64.exe /ErrorStdOut tests\run_tests.ahk [part of a test name]
;
; Prints a line per failed test and a summary, and exits with 0 if all passed.
; The button finder has its own check on screenshots: tests\vision_cases.ahk.
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
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
#Include ..\src\Updater.ahk
#Include ..\src\SetupWindow.ahk
#Include ..\src\SelfTest.ahk
#Include ..\src\Commands.ahk
#Include Fakes.ahk
#Include RunnerTests.ahk
#Include GameTests.ahk
#Include MiscTests.ahk
#Include UpdateTests.ahk
#Include WindowTests.ahk

Say(text) => FileAppend(text "`n", "*", "UTF-8")

; Print errors instead of showing a dialog nobody can click.
OnError(Crashed)
Crashed(err, mode) {
    Say("CRASH: " Type(err) ": " err.Message (err.HasProp("Extra") && err.Extra != "" ? " (" err.Extra ")" : "") "`n" err.Stack)
    ExitApp(2)
}

RunAll()

RunAll() {
    suites := [RunnerTests, GameTests, MiscTests, UpdateTests, WindowTests]
    filter := A_Args.Length ? A_Args[1] : ""
    root := A_Temp "\synseeder-tests"
    passed := 0, failed := []
    for suite in suites {
        suiteName := suite.Prototype.__Class
        names := []
        for name in suite.OwnProps()
            if SubStr(name, 1, 5) = "Test_" && (filter = "" || InStr(suiteName "." name, filter))
                names.Push(name)
        for name in names {
            try DirDelete(root, true)
            App.dirOverride := root "\app"
            Logs.path := "", Logs.capture := "", Logs.echo := false
            try {
                suite.%name%()
                passed++
            } catch as err {
                where := ""
                if err.HasProp("Stack")
                    for line in StrSplit(err.Stack, "`n")
                        if InStr(line, "Tests.ahk") {
                            where := RegExReplace(Trim(line), "^.*\\", "")
                            break
                        }
                failed.Push(suiteName "." SubStr(name, 6) ": " Type(err) ": " err.Message
                    . (err.HasProp("Extra") && err.Extra != "" ? " (" err.Extra ")" : "") "`n      at " where)
            } finally {
                Patches.Undo()
                App.dirOverride := ""
            }
        }
    }
    try DirDelete(root, true)
    for line in failed
        Say("FAIL " line)
    Say(passed " passed, " failed.Length " failed")
    ExitApp(failed.Length ? 1 : 0)
}
