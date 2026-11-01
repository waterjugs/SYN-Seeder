#Requires AutoHotkey v2.0
;@Ahk2Exe-SetName SynSeeder
;@Ahk2Exe-SetDescription SynSeeder
;@Ahk2Exe-SetVersion 0.9.0
;@Ahk2Exe-SetCompanyName waterjugs
;@Ahk2Exe-SetCopyright Copyright (c) waterjugs
;@Ahk2Exe-SetOrigFilename SynSeeder.exe
;@Ahk2Exe-SetMainIcon ..\..\assets\synseeder.ico
; Trial baseline: only a window, to compare against the others.
g := Gui(, "SynSeeder")
g.SetFont("s10", "Segoe UI")
g.Add("Text", , "SynSeeder")
g.Add("Button", "w80", "Close").OnEvent("Click", (*) => ExitApp())
g.OnEvent("Close", (*) => ExitApp())
g.Show()
