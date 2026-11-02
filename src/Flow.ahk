; In-game navigation for HLL Vietnam, as of build v1.7 (Oct 2026).
;
; What joining looks like in this version:
;
;   splash ("press any button") -> main menu (ENLIST) -> server browser
;   (search, JOIN on the server's row) -> Select Force (US or NVA; skipped
;   when rejoining a server you were just on) -> Units (SWITCH TEAM is
;   available; the seeder always creates its own infantry squad: + opens a
;   Create a Unit popup whose CREATE UNIT button makes you its squad leader)
;   -> Edit Roles (F confirms) -> Deployment (F deploys at the selected HQ)
;   -> in game.
;
; Admin messages pop up with a "[Y] YES" button, and Esc opens a game menu;
; both are overlays that can show up in game too. Each tick looks at the
; screen, works out which of these it is, and does the one thing that moves
; it forward. So the same code handles a fresh launch, a kick back to the
; main menu, a new map and a death.

class Flow {
    ; Screens in the order they're checked. Overlays come first.
    static OVERLAYS := ["admin_yes", "game_menu_leave"]
    static SCREENS := ["admin_yes", "game_menu_leave", "deploy_button", "roles_confirm", "select_force",
        "create_unit", "switch_team", "server_row", "browser_search", "browser_refresh", "menu_enlist"]

    ; Parts of the Units screen, as [left, top, right, bottom] fractions of the 16:9 menu area.
    static INFANTRY_CREATE := [0.29, 0.10, 0.53, 0.22]
    static FACTION_BADGE := [0.0, 0.75, 0.12, 0.95]
    ; The two cards on Select Force: team -> [button, region].
    static FORCE_CARDS := Map("allies", ["force_us", [0.05, 0.30, 0.50, 0.55]],
        "axis", ["force_nva", [0.50, 0.30, 0.95, 0.55]])
    static FORCE_TRIES := 5   ; clicks (~10 s) on one card before trying the other, in case it's locked
    static ADMIN_CLICKS := 2  ; clicks on an admin message's YES before also trying its Y key
    ; The bottom right of the Create a Unit popup, where its CREATE UNIT button is.
    static CREATE_UNIT_BUTTON := [0.55, 0.60, 0.95, 0.90]

    static REFRESH_EVERY := 20     ; seconds between server list refreshes while our server is missing
    static STUCK_TICKS := 90       ; ~3 minutes on a screen we don't know (a map load takes 1-2) before a screenshot
    static STUCK_REPEATS := 15     ; the same screen this many ticks in a row also gets a screenshot
    static KEEP_SCREENSHOTS := 20  ; newest debug screenshots kept

    static IsOverlay(name) => name = "admin_yes" || name = "game_menu_leave"

    ; Which menu is showing, or "" when in game or loading.
    static CurrentScreen(screen) {
        screen.Refresh()
        for name in Flow.SCREENS
            if screen.Find(name)
                return name
        return ""
    }

    ; A small strafe so the idle kick doesn't trigger.
    static Nudge(screen) {
        screen.Hold("a", 0.3)
        screen.Hold("d", 0.3)
    }
}

; Walks from wherever the game is to deployed on the server.
;
; ``side`` is called whenever a team decision comes up and returns the team
; that needs players ("allies" or "axis"), or "" to keep the game's pick.
; ``pick`` returns the team to choose on Select Force (the smaller one).
; ``focus`` brings the game to the front and says whether it is; no input is
; sent while it isn't. ``waiting`` says whether that's because someone is
; using the PC, which doesn't count against timeouts. ``alive`` says whether
; the game is still running.
class Navigator {
    static FOREVER := 1.0e15  ; a deadline that never comes

    __New(screen, config, clock, side, focus := "", alive := "", pick := "", waiting := "") {
        this.screen := screen
        this.config := config
        this.clock := clock
        this.side := side
        this.pick := pick ? pick : () => "allies"
        this.focus := focus ? focus : () => true
        this.waiting := waiting ? waiting : () => false
        this.alive := alive ? alive : () => true
        this.switchedTeam := false
        ; True from deploying on, when the mouse aims instead of clicking menus.
        this.inGame := false
        this.adminClicks := 0
        this.forceTries := 0
        this.forceTeam := ""
        this.lastRefresh := -Navigator.FOREVER
    }

    ; True once deployed (or back in game), false if that didn't happen in
    ; time or the game closed.
    ;
    ; ``freshLaunch`` means the game was just started, so a blank screen is
    ; the splash waiting for a key rather than gameplay. Time spent waiting
    ; for someone to stop using the PC extends ``timeout``, but never past
    ; ``latest`` (a clock.Now() time).
    GetIn(timeout, freshLaunch := false, latest := Navigator.FOREVER) {
        clock := this.clock
        deadline := clock.Now() + timeout
        ; One team switch per trip in; a later rejoin may need another.
        this.switchedTeam := false
        this.inGame := false
        this.adminClicks := 0
        seen := Map()
        deployed := false
        quietTicks := 0, unknownTicks := 0
        last := "", repeats := 0
        while clock.Now() < deadline {
            if !(this.alive)() {
                Logs.Warning("The game closed while getting into the server")
                return false
            }
            if !(this.focus)() {
                start := clock.Now()
                clock.Sleep(2)
                if (this.waiting)()  ; the player has the PC; that isn't the game being stuck
                    deadline := Min(deadline + clock.Now() - start, latest)
                continue
            }
            name := Flow.CurrentScreen(this.screen)
            if name != "admin_yes"
                this.adminClicks := 0  ; each message gets its own clicks
            if name = "" {
                onlyOverlays := true  ; nothing but overlays (or nothing) seen so far
                for key in seen
                    if !Flow.IsOverlay(key)
                        onlyOverlays := false
                if deployed || (!freshLaunch && onlyOverlays) {
                    this.inGame := true
                    quietTicks++
                    if quietTicks >= 3 {
                        Logs.Info("In game")
                        return true
                    }
                } else {
                    if freshLaunch && onlyOverlays
                        this.screen.Press("space")  ; splash / "press any button"
                    unknownTicks++
                    if unknownTicks = Flow.STUCK_TICKS
                        this.Snapshot("unrecognised screen for 3 minutes")
                }
                clock.Sleep(2)
                continue
            }
            quietTicks := 0, unknownTicks := 0
            repeats := name == last ? repeats + 1 : 0
            last := name
            if !seen.Has(name)
                Logs.Info("On screen: " name)
            seen[name] := true
            if !Flow.IsOverlay(name) {
                deployed := name = "deploy_button"
                this.inGame := false
            }
            if !Flow.IsOverlay(name) && name != "select_force"
                this.forceTries := 0, this.forceTeam := ""
            this.Handle(name)
            ; After acting, so the screenshot can't replace the frame the handler used.
            if repeats = Flow.STUCK_REPEATS && name != "browser_refresh"  ; waiting on the list is normal
                this.Snapshot("still on " name " after " Flow.STUCK_REPEATS " tries")
            clock.Sleep(2)
        }
        Logs.Warning("Couldn't get into the server within " Round(timeout) "s")
        return false
    }

    ; Saves what's on screen so an unexpected menu can be added later.
    Snapshot(why) {
        if !HasMethod(this.screen, "SaveScreenshot") {
            Logs.Warning("Stuck: " why)
            return
        }
        try {
            folder := App.Dir "\debug"
            DirCreate(folder)
            path := folder "\" FormatTime(, "yyyyMMdd-HHmmss") ".png"
            this.screen.SaveScreenshot(path)
        } catch as err {  ; a failed debug screenshot must not end the run
            Logs.Warning("Stuck: " why " (screenshot failed: " err.Message ")")
            return
        }
        Logs.Warning("Stuck: " why ". Saved " path)
        ; Names sort oldest first; keep the folder from growing forever.
        names := ""
        loop files folder "\*.png"
            names .= A_LoopFileName "`n"
        names := StrSplit(Sort(RTrim(names, "`n"), "C"), "`n")
        loop names.Length - Flow.KEEP_SCREENSHOTS
            try FileDelete(folder "\" names[A_Index])  ; e.g. open in a viewer
    }

    Handle(name) {
        switch name, true {
            case "admin_yes": this.OnAdminYes()
            case "game_menu_leave": this.OnGameMenuLeave()
            case "deploy_button": this.OnDeployButton()
            case "roles_confirm": this.OnRolesConfirm()
            case "select_force": this.OnSelectForce()
            case "create_unit": this.OnCreateUnit()
            case "switch_team": this.OnSwitchTeam()
            case "server_row": this.OnServerRow()
            case "browser_search": this.OnBrowserSearch()
            case "browser_refresh": this.OnBrowserRefresh()
            case "menu_enlist": this.OnMenuEnlist()
            default: throw ValueError("No handler for the screen " name)
        }
    }

    ; One handler per screen in Flow.SCREENS.

    OnAdminYes() {
        ; Over gameplay the mouse aims, so a click fires the weapon and the
        ; message stays up (10/28: 8 minutes of it); there, press its Y key.
        ; Menus still show around the message: over one, click YES, which
        ; always works there, and mix in Y if a couple of clicks haven't.
        menu := false
        for other in Flow.SCREENS {
            if !Flow.IsOverlay(other) && this.screen.Find(other) {
                menu := true
                break
            }
        }
        if this.inGame && !menu {
            this.screen.Press("y")
            return
        }
        this.adminClicks++
        if this.adminClicks > Flow.ADMIN_CLICKS && Mod(this.adminClicks, 2)
            this.screen.Press("y")
        else
            this.screen.Click(this.screen.Find("admin_yes"))
    }

    OnGameMenuLeave() => this.screen.Press("esc")

    OnDeployButton() {
        this.screen.Press("f")
        this.inGame := true  ; until a menu shows again
    }

    OnRolesConfirm() => this.screen.Press("f")

    OnSelectForce() {
        if this.forceTeam = ""
            this.forceTeam := (this.pick)()  ; once per visit, so the choice can't flip mid-way
        team := this.forceTeam = "axis" ? "axis" : "allies"
        other := team = "allies" ? "axis" : "allies"
        if Mod(this.forceTries // Flow.FORCE_TRIES, 2) {
            ; Still here after several clicks: that card may be locked. Take
            ; turns between the two so a slow screen still ends up on ours.
            swap := team, team := other, other := swap
        }
        card := this.screen.Find(Flow.FORCE_CARDS[team]*)
        if !card {
            team := other
            card := this.screen.Find(Flow.FORCE_CARDS[other]*)
        }
        if !card {
            Logs.Warning("Couldn't find the US or NVA card on Select Force")
            return
        }
        if Mod(this.forceTries, Flow.FORCE_TRIES) = 0
            Logs.Info("Picking " (team = "allies" ? "US" : "NVA"))
        this.forceTries++
        this.switchedTeam := true  ; chosen deliberately; don't switch again on Units
        this.screen.Click(card)
    }

    OnCreateUnit() {
        button := this.screen.Find("create_unit_button", Flow.CREATE_UNIT_BUTTON)
        if button {
            Logs.Info("Creating the unit")
            this.screen.Click(button)
        }
    }

    OnSwitchTeam() {
        wanted := (this.side)()
        current := this.screen.Find("faction_nva", Flow.FACTION_BADGE) ? "axis" : "allies"
        if wanted != "" && wanted != current && !this.switchedTeam {
            Logs.Info("Switching from " current " to " wanted)
            this.switchedTeam := true
            this.screen.Click(this.screen.Find("switch_team"))
            return
        }
        ; Always lead a new squad of our own, never join someone else's
        ; (Syndicate's rule for seeders), so real players have one to join.
        create := this.screen.Find("infantry_create", Flow.INFANTRY_CREATE)
        if create {
            Logs.Info("Creating an infantry squad")
            this.screen.Click(create)
        }
    }

    OnServerRow() {
        row := this.screen.Find("server_row")
        joins := this.screen.FindAll("browser_join")
        if !row || !joins.Length
            return
        ; The JOIN button on the same row as the server's name.
        join := joins[1]
        for pos in joins
            if Abs(pos[2] - row[2]) < Abs(join[2] - row[2])
                join := pos
        this.screen.Click(join)
    }

    OnBrowserSearch() {
        this.screen.Click(this.screen.Find("browser_search"))
        this.clock.Sleep(0.5)
        this.screen.TypeText(this.config.server_search)
        this.screen.Press("enter")
        this.lastRefresh := this.clock.Now()
        this.clock.Sleep(2)
    }

    OnBrowserRefresh() {
        ; Searched, but our server isn't listed (yet): it may be restarting.
        if this.clock.Now() - this.lastRefresh >= Flow.REFRESH_EVERY {
            Logs.Info("Server not in the list; refreshing")
            this.screen.Press("r")
            this.lastRefresh := this.clock.Now()
        }
    }

    OnMenuEnlist() {
        this.screen.Click(this.screen.Find("menu_enlist"))
        this.clock.Sleep(3)
    }
}
