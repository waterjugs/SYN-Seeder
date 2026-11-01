; The bare trial's whole program: only a window, to compare against the others.
g := Gui(, "SynSeeder")
g.SetFont("s10", "Segoe UI")
g.Add("Text", , "SynSeeder")
g.Add("Button", "w80", "Close").OnEvent("Click", (*) => ExitApp())
g.OnEvent("Close", (*) => ExitApp())
g.Show()
