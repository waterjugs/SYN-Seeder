; SynSeeder: seeds an HLL Vietnam server by joining it at a set time each day,
; and when a seed is called on Discord if the player ticks Seed when pinged.
;
;   SynSeeder.exe            the setup window: start time, launcher, seed now/stop
;   SynSeeder.exe --seed     seed now; what the daily task runs
;                            (--max-minutes N ends the run after N minutes, for testing)
;   SynSeeder.exe --check-seed-calls   one check for a seed call; what the
;                            seed-calls task runs about once a minute
;   SynSeeder.exe --record   a screenshot every few seconds while you click
;                            through the menus yourself, to make button images
;                            (--minutes N, --every SECONDS)
;   SynSeeder.exe --selftest LOG   checks the parts that don't need the game (CI)
;
; A release build checks for a newer release before each seeding run and
; hands the run over to it (see src\Updater.ahk).
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn LocalSameAsGlobal, Off
;@Ahk2Exe-SetName SynSeeder
;@Ahk2Exe-SetDescription SynSeeder
;@Ahk2Exe-SetVersion 1.1.0
;@Ahk2Exe-SetCompanyName waterjugs
;@Ahk2Exe-SetCopyright Copyright (c) waterjugs
;@Ahk2Exe-SetOrigFilename SynSeeder.exe
;@Ahk2Exe-SetMainIcon assets\synseeder.ico

#Include src\Build.ahk
#Include src\App.ahk
#Include src\Json.ahk
#Include src\Config.ahk
#Include src\Http.ahk
#Include src\Gdip.ahk
#Include src\Vision.ahk
#Include src\ButtonFiles.ahk
#Include src\Buttons.ahk
#Include src\WinApi.ahk
#Include src\GameScreen.ahk
#Include src\Flow.ahk
#Include src\HllGame.ahk
#Include src\Runner.ahk
#Include src\SeedLock.ahk
#Include src\DailyTask.ahk
#Include src\SeedCalls.ahk
#Include src\Updater.ahk
#Include src\FontFiles.ahk
#Include src\Look.ahk
#Include src\SetupWindow.ahk
#Include src\SelfTest.ahk
#Include src\Commands.ahk

Main()

Main() {
    opts := ParseArgs(A_Args)
    if opts.selftest {
        ExitApp(SelfTest.Run(opts.selftestLog))
    }
    if opts.checkSeedCalls {
        ; Before anything else: once a minute, this mustn't log a broken
        ; settings file, and it ends Windows' "app starting" pointer at once.
        Sleep(-1)
        Logs.Open()
        try {
            code := SeedCalls.Check()
        } catch as err {  ; no console in the built exe, and no dialog every minute either
            Logs.Exception("Seed call: the check crashed", err)
            code := 2
        }
        ExitApp(code)
    }
    Logs.Open()
    try {
        config := SeederConfig.Load()
    } catch as err {
        Logs.Error("Settings file " SeederConfig.DefaultPath " is broken (" err.Message "); using defaults")
        config := SeederConfig()
    }
    if opts.unknown.Length
        Logs.Warning("Ignoring unknown arguments: " JoinList(opts.unknown, " "))
    if opts.record
        ExitApp(RunRecord(opts.minutes, opts.every))
    if opts.seed {
        if opts.maxMinutes
            config.max_minutes := opts.maxMinutes
        ExitApp(RunSeed(config, opts.passOn, opts.installTo, opts.oldPids))
    }
    SetupWindow(config)
}
