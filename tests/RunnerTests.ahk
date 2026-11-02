; The seeding run and the menu steps, on the fakes (ported from the first
; SynSeeder's tests/test_runner.py).

MakeRun(running := false, launchOk := true) {
    screen := FakeScreen(HappyPath())
    game := FakeGame(screen, running, launchOk)
    return {config: SeederConfig(), game: game, screen: screen, clock: FakeClock()}
}

; A fetch that counts its calls and runs ``each(n)`` before answering ``answer(n)``.
Counted(answer, each := "") {
    calls := {n: 0}
    fetch(url) {
        calls.n++
        if each
            each(calls.n)
        return answer(calls.n)
    }
    return fetch
}

; Wraps ``fetch`` and the game's Close to note when counts came in and when the game closed.
Watch(game, clock, fetch) {
    readings := [], closes := []
    realClose := game.GetMethod("Close")
    timedClose(this, linger := 0) {
        closes.Push(clock.at)
        realClose(this, linger)
    }
    game.DefineProp("Close", {Call: timedClose})
    timedFetch(url) {
        status := fetch(url)
        readings.Push([clock.at, status ? status.players : ""])
        return status
    }
    return {fetch: timedFetch, readings: readings, closes: closes}
}

; When the count last went from under ``threshold`` to at or over it.
LastReached(readings, threshold := 80) {
    at := ""
    loop readings.Length - 1 {
        before := readings[A_Index][2], now := readings[A_Index + 1]
        if now[2] != "" && before != "" && now[2] >= threshold && threshold > before
            at := now[1]
    }
    return at
}

; Clicks on ``card`` do nothing until the ``acceptAfter``-th one.
SlowCard(screen, card, acceptAfter) {
    realClick := screen.GetMethod("Click")
    count := {n: 0}
    slowClick(this, pos) {
        if pos[1] == card {
            count.n++
            if count.n < acceptAfter {
                this.clicks.Push(card)
                return
            }
        }
        realClick(this, pos)
    }
    screen.DefineProp("Click", {Call: slowClick})
}

class RunnerTests {
    static Test_skips_when_already_seeded() {
        r := MakeRun()
        AssertEq(SeedWith(r.config, r.game, r.screen, Statuses([85]), r.clock), Runner.ALREADY_SEEDED)
        AssertEq(r.game.launches, 0)
    }

    static Test_skips_when_server_down() {
        r := MakeRun()
        AssertEq(SeedWith(r.config, r.game, r.screen, Statuses([""]), r.clock), Runner.SERVER_DOWN)
        AssertEq(r.game.launches, 0)
    }

    static Test_leaves_a_running_game_alone() {
        r := MakeRun(true)
        AssertEq(SeedWith(r.config, r.game, r.screen, Statuses([10]), r.clock), Runner.GAME_IN_USE)
        AssertEq(r.game.closes, 0)
        AssertEq(r.screen.clicks, [])
        AssertEq(r.screen.keys, [])
    }

    static Test_full_join_then_leaves_once_seeded() {
        r := MakeRun()
        AssertEq(SeedWith(r.config, r.game, r.screen, Statuses([10, 10, 40, 79, 80]), r.clock), Runner.SEEDED)
        AssertEq(r.screen.typed, ["syndicate"])
        AssertEq(r.screen.clicks, ["menu_enlist", "browser_search", "browser_join", "admin_yes", "force_us",
            "infantry_create", "create_unit_button"])  ; never an open squad
        AssertEq(Slice(r.screen.keys, 1, 2), ["space", "enter"])
        AssertEq(Only(r.screen.keys, "f"), ["f", "f"])
        Assert(r.game.launches = 1 && !r.game.isRunning)
    }

    static Test_keeps_game_team_when_balanced() {
        r := MakeRun()
        SeedWith(r.config, r.game, r.screen, Statuses([11, 80]), r.clock)  ; 6 v 5
        Assert(!Includes(r.screen.clicks, "switch_team"))
    }

    static Test_select_force_picks_the_smaller_team() {
        r := MakeRun()
        SeedWith(r.config, r.game, r.screen, Statuses([11, 80]), r.clock)  ; allies 6, axis 5
        Assert(Includes(r.screen.clicks, "force_nva") && !Includes(r.screen.clicks, "force_us"))
        Assert(!Includes(r.screen.clicks, "switch_team"))
    }

    static Test_switches_to_the_short_team_once() {
        ; Rejoining skips Select Force; the game put us on NVA (the fake shows
        ; its badge) while NVA is 6 ahead.
        r := MakeRun()
        path := HappyPath()
        path["browser_join"] := [["server_row", "browser_join", "browser_refresh"], UNITS]
        r.screen.transitions := path
        screen := r.screen
        fetch(url) => FakeStatus(Count(screen.clicks, "create_unit_button") ? 80 : 20, 7, 13, "S")
        SeedWith(r.config, r.game, r.screen, fetch, r.clock)
        AssertEq(Count(r.screen.clicks, "switch_team"), 1)
        Assert(IndexOf(r.screen.clicks, "switch_team") < IndexOf(r.screen.clicks, "infantry_create"))
    }

    static Test_always_creates_its_own_squad() {
        r := MakeRun()
        SeedWith(r.config, r.game, r.screen, Statuses([10, 80]), r.clock)
        AssertEq(Slice(r.screen.clicks, r.screen.clicks.Length - 1), ["infantry_create", "create_unit_button"])
        Assert(!r.screen.visible.Has("roles_confirm"))
        AssertEq(Only(r.screen.keys, "f"), ["f", "f"])
    }

    static Test_never_joins_someone_elses_squad() {
        screen := FakeScreen(Map())
        screen.Show("switch_team")
        screen.DefineProp("FindAll", {Call: (this, name, region := "") => [[100, 300], [100, 360]]})  ; open squads
        screen.DefineProp("Find", {Call: (this, name, region := "") => name == "infantry_create" ? [200, 100] : ""})
        clicked := []
        screen.DefineProp("Click", {Call: (this, pos) => clicked.Push(pos)})
        nav := Navigator(screen, SeederConfig(), FakeClock(), () => "")
        loop 3
            nav.Handle("switch_team")
        AssertEq(clicked, [[200, 100], [200, 100], [200, 100]])  ; the + every time, never a squad
    }

    static Test_creates_a_new_squad_after_a_map_change() {
        ; A new map sends everyone back to Units; still under 80, so lead a new squad.
        r := MakeRun()
        screen := r.screen
        each(n) {
            if n = 3
                screen.Show("switch_team", "squad_join", "infantry_create")
        }
        fetch := Counted(n => FakeStatus(n >= 6 ? 80 : 20, 10, 10, "S"), each)
        AssertEq(SeedWith(r.config, r.game, r.screen, fetch, r.clock), Runner.SEEDED)
        AssertEq(Count(r.screen.clicks, "infantry_create"), 2)
        AssertEq(Count(r.screen.clicks, "create_unit_button"), 2)
        Assert(!Includes(r.screen.clicks, "squad_join"))
        AssertEq(r.game.launches, 1)
    }

    static Test_leaves_instead_of_a_new_squad_once_seeded_at_a_map_change() {
        r := MakeRun()
        calls := {n: 0}
        screen := r.screen, config := r.config
        clock := FakeClock()
        clock.DefineProp("Sleep", {Call: mapChangeSleep})
        mapChangeSleep(this, seconds) {
            this.at += seconds
            if calls.n = 2 && seconds = config.poll_seconds  ; the new map loads while it waits
                screen.Show("switch_team", "squad_join", "infantry_create")
        }
        fetch(url) {
            calls.n++
            return FakeStatus(calls.n >= 3 ? 80 : 20, 10, 10, "S")
        }
        AssertEq(SeedWith(r.config, r.game, r.screen, fetch, clock), Runner.SEEDED)
        AssertEq(Count(r.screen.clicks, "infantry_create"), 1)  ; the count is checked before the screen
        Assert(!r.game.isRunning)
    }

    static Test_select_force_tries_the_other_card_when_one_is_locked() {
        r := MakeRun()
        path := HappyPath()
        path["force_us"] := [[], []]  ; US is locked: clicking it does nothing
        r.screen.transitions := path
        AssertEq(SeedWith(r.config, r.game, r.screen, Statuses([10, 80]), r.clock), Runner.SEEDED)
        AssertEq(Count(r.screen.clicks, "force_us"), Flow.FORCE_TRIES)
        AssertEq(Count(r.screen.clicks, "force_nva"), 1)
    }

    static Test_select_force_waits_for_a_slow_screen_before_trying_the_other_card() {
        ; US only takes on the 4th click (~8 s) because the screen is still loading.
        r := MakeRun()
        SlowCard(r.screen, "force_us", 4)
        SeedWith(r.config, r.game, r.screen, Statuses([10, 80]), r.clock)
        AssertEq(Count(r.screen.clicks, "force_us"), 4)
        Assert(!Includes(r.screen.clicks, "force_nva"))
    }

    static Test_select_force_takes_turns_when_neither_card_takes_at_first() {
        ; US is slow to accept and NVA is locked: it goes back to US.
        r := MakeRun()
        path := HappyPath()
        path["force_nva"] := [[], []]
        r.screen.transitions := path
        SlowCard(r.screen, "force_us", Flow.FORCE_TRIES + 1)
        AssertEq(SeedWith(r.config, r.game, r.screen, Statuses([10, 80]), r.clock), Runner.SEEDED)
        AssertEq(Count(r.screen.clicks, "force_us"), Flow.FORCE_TRIES + 1)
        AssertEq(Count(r.screen.clicks, "force_nva"), Flow.FORCE_TRIES)
    }

    static Test_select_force_uses_the_other_card_when_one_is_missing() {
        r := MakeRun()
        path := HappyPath()
        path["browser_join"] := [["server_row", "browser_join", "browser_refresh"], ["select_force", "force_nva"]]
        r.screen.transitions := path
        AssertEq(SeedWith(r.config, r.game, r.screen, Statuses([10, 80]), r.clock), Runner.SEEDED)
        Assert(Includes(r.screen.clicks, "force_nva") && !Includes(r.screen.clicks, "force_us"))
    }

    static Test_select_force_uses_current_team_counts() {
        ; Allies were short when the run started, but by the time Select Force
        ; shows (after a slow launch) NVA is.
        r := MakeRun()
        clock := r.clock
        realLaunch := r.game.GetMethod("Launch")
        slowLaunch(this, timeout := "") {
            clock.Sleep(60)
            return realLaunch(this, timeout)
        }
        r.game.DefineProp("Launch", {Call: slowLaunch})
        later := Statuses([10, 10, 80], false)  ; 5 v 5 first...
        counts := [FakeStatus(10, 3, 7, "S"), FakeStatus(11, 7, 4, "S")]
        changing(url) => counts.Length ? counts.RemoveAt(1) : later(url)
        SeedWith(r.config, r.game, r.screen, changing, r.clock)
        Assert(Includes(r.screen.clicks, "force_nva") && !Includes(r.screen.clicks, "force_us"))
    }

    static Test_rejoin_can_switch_team_again() {
        ; Picked US on Select Force; later kicked to the menu and rejoined onto
        ; NVA while NVA is well ahead: switching is allowed again.
        r := MakeRun()
        screen := r.screen
        each(n) {
            if n = 3 {
                screen.Show("menu_enlist")
                path := HappyPath()
                path["browser_join"] := [["server_row", "browser_join", "browser_refresh"], UNITS]
                screen.transitions := path
            }
        }
        fetch := Counted(n => FakeStatus(n >= 8 ? 80 : 20, 7, 13, "S"), each)
        AssertEq(SeedWith(r.config, r.game, r.screen, fetch, r.clock), Runner.SEEDED)
        Assert(Includes(r.screen.clicks, "force_us"))
        AssertEq(Count(r.screen.clicks, "switch_team"), 1)
    }

    static Test_short_test_runs_still_launch() {
        r := MakeRun()
        r.config.max_minutes := 5
        SeedWith(r.config, r.game, r.screen, Statuses([10]), r.clock)
        AssertEq(r.game.launches, 1)
    }

    static Test_short_runs_keep_to_their_time_limit() {
        ; A slow launch, then a menu the bot never recognises.
        r := MakeRun()
        r.config.max_minutes := 5
        clock := r.clock, screen := r.screen
        realLaunch := r.game.GetMethod("Launch")
        slowLaunch(this, timeout := "") {
            clock.Sleep(250)
            realLaunch(this, timeout)
            screen.Show("something_new")
            return true
        }
        r.game.DefineProp("Launch", {Call: slowLaunch})
        AssertEq(SeedWith(r.config, r.game, r.screen, Statuses([10]), r.clock), Runner.TIMED_OUT)
        Assert(r.clock.at <= 5 * 60 + 20, "ran until " r.clock.at)
    }

    static Test_failed_late_launch_is_watched_for() {
        ; Steam is slow (e.g. updating); the run ends before the game appears.
        r := MakeRun(false, false)
        r.config.max_minutes := 5
        AssertEq(SeedWith(r.config, r.game, r.screen, Statuses([10]), r.clock), Runner.TIMED_OUT)
        AssertEq(r.game.lingered, 90)
    }

    static Test_restarts_after_crash() {
        r := MakeRun()
        game := r.game, screen := r.screen
        each(n) {
            if n = 3 {  ; crash while seeding
                game.isRunning := false
                screen.Show()
            }
        }
        fetch := Counted(n => FakeStatus(n >= 6 ? 80 : 10, 5, 5, "S"), each)
        AssertEq(SeedWith(r.config, r.game, r.screen, fetch, r.clock), Runner.SEEDED)
        AssertEq(r.game.launches, 2)
    }

    static Test_rejoins_after_kick_to_menu() {
        r := MakeRun()
        screen := r.screen
        each(n) {
            if n = 3
                screen.Show("menu_enlist")
        }
        fetch := Counted(n => FakeStatus(n >= 6 ? 80 : 20, 10, 10, "S"), each)
        AssertEq(SeedWith(r.config, r.game, r.screen, fetch, r.clock), Runner.SEEDED)
        AssertEq(Count(r.screen.clicks, "browser_join"), 2)
        AssertEq(r.game.launches, 1)
    }

    static Test_redeploys_after_death_or_new_map() {
        r := MakeRun()
        screen := r.screen
        each(n) {
            if n = 3
                screen.Show("deploy_button")
        }
        fetch := Counted(n => FakeStatus(n >= 6 ? 80 : 20, 10, 10, "S"), each)
        AssertEq(SeedWith(r.config, r.game, r.screen, fetch, r.clock), Runner.SEEDED)
        AssertEq(Count(r.screen.keys, "f"), 3)  ; role, deploy, redeploy
    }

    static Test_overlays_in_game_are_closed_without_leaving() {
        r := MakeRun()
        screen := r.screen
        each(n) {
            if n = 3
                screen.Show("admin_yes")
            if n = 5
                screen.Show("game_menu_leave")
        }
        fetch := Counted(n => FakeStatus(n >= 8 ? 80 : 20, 10, 10, "S"), each)
        AssertEq(SeedWith(r.config, r.game, r.screen, fetch, r.clock), Runner.SEEDED)
        Assert(r.game.launches = 1 && r.game.closes = 1)
        ; Clicked over the menus while joining; in game a click would fire the
        ; weapon, so there it's closed with its Y key.
        AssertEq(Count(r.screen.clicks, "admin_yes"), 1)
        AssertEq(Count(r.screen.keys, "y"), 1)
        Assert(Includes(r.screen.keys, "esc"))
        AssertEq(Count(r.screen.keys, "space"), 1)  ; only the splash, never in game
    }

    static Test_admin_message_right_after_deploying_is_closed_with_y() {
        ; 10/28: the message came up just after F on Deployment, over gameplay,
        ; where clicks fire the weapon and never reach it.
        path := HappyPath()
        path["browser_join"] := [path["browser_join"][1], ["select_force", "force_us", "force_nva"]]
        path["deploy_button|f"] := [["deploy_button"], ["admin_yes"]]
        path["admin_yes"] := [[], []]
        screen := FakeScreen(path)
        game := FakeGame(screen), clock := FakeClock()
        AssertEq(SeedWith(SeederConfig(), game, screen, Statuses([10, 10, 80]), clock), Runner.SEEDED)
        Assert(!Includes(screen.clicks, "admin_yes"))
        AssertEq(Count(screen.keys, "y"), 1)
    }

    static Test_admin_message_over_a_menu_gets_y_if_clicks_do_not_close_it() {
        path := HappyPath()
        path["admin_yes"] := [[], []]
        screen := FakeScreen(path)
        game := FakeGame(screen), clock := FakeClock()
        AssertEq(SeedWith(SeederConfig(), game, screen, Statuses([10, 10, 80]), clock), Runner.SEEDED)
        AssertEq(Count(screen.clicks, "admin_yes"), Flow.ADMIN_CLICKS)
        AssertEq(Count(screen.keys, "y"), 1)
    }

    static Test_admin_message_over_a_menu_in_game_is_clicked_and_it_walks_back_in() {
        ; e.g. a death or a map change brings up a menu with a message over it
        path := HappyPath()
        path["admin_yes|y"] := [[], []]  ; Y has only been seen to work over gameplay; over a menu, a click
        screen := FakeScreen(path)
        game := FakeGame(screen), clock := FakeClock()
        each(n) {
            if n = 3
                screen.Show(UNITS*), screen.visible["admin_yes"] := true
        }
        fetch := Counted(n => FakeStatus(n >= 8 ? 80 : 20, 10, 10, "S"), each)
        AssertEq(SeedWith(SeederConfig(), game, screen, fetch, clock), Runner.SEEDED)
        AssertEq(Count(screen.clicks, "admin_yes"), 2)  ; joining, then over Units
        AssertEq(Count(screen.clicks, "infantry_create"), 2)
    }

    static Test_queued_admin_messages_over_a_menu_are_all_clicked_away() {
        ; Three messages, each replaced by the next as soon as it's clicked.
        path := HappyPath()
        path["admin_yes|y"] := [[], []]
        screen := FakeScreen(path)
        left := {n: 3}
        realClick := screen.GetMethod("Click")
        clickOne(this, pos) {
            realClick(this, pos)
            if this.clicks[this.clicks.Length] == "admin_yes" {
                left.n--
                if left.n
                    this.visible["admin_yes"] := true  ; the next one
            }
        }
        screen.DefineProp("Click", {Call: clickOne})
        game := FakeGame(screen), clock := FakeClock()
        AssertEq(SeedWith(SeederConfig(), game, screen, Statuses([10, 10, 80]), clock), Runner.SEEDED)
        AssertEq(Count(screen.clicks, "admin_yes"), 3)
        Assert(Count(screen.keys, "y") <= 1)  ; at most one Y tried in between
    }

    static Test_no_input_while_game_is_not_in_front() {
        r := MakeRun()
        r.game.focused := false
        r.config.max_minutes := 15
        SeedWith(r.config, r.game, r.screen, Statuses([10]), r.clock)
        AssertEq(r.screen.clicks, [])
        AssertEq(r.screen.keys, [])
        AssertEq(r.screen.typed, [])
    }

    static Test_waiting_for_someone_using_the_pc_does_not_use_up_the_join_time() {
        r := MakeRun()
        game := BusyGame(r.screen, r.clock, r.config.launch_timeout + r.config.load_timeout + 600)
        AssertEq(SeedWith(r.config, game, r.screen, Statuses([10, 10, 80]), r.clock), Runner.SEEDED)
        AssertEq(game.launches, 1)  ; no give-up and relaunch while they were busy
    }

    static Test_waiting_for_someone_using_the_pc_still_ends_at_the_time_limit() {
        r := MakeRun()
        r.config.max_minutes := 30
        game := BusyGame(r.screen, r.clock, 10 * 60 * 60)
        AssertEq(SeedWith(r.config, game, r.screen, Statuses([10]), r.clock), Runner.TIMED_OUT)
        Assert(r.clock.at <= 30 * 60 + 60, "ran until " r.clock.at)
        Assert(game.launches = 1 && !game.isRunning)
        AssertEq(r.screen.clicks, [])
        AssertEq(r.screen.keys, [])
    }

    static Test_crash_during_navigation_is_noticed_at_once() {
        screen := FakeScreen(HappyPath())
        screen.Show("menu_enlist")
        clock := FakeClock()
        answers := [true, true, false]
        alive() => answers.RemoveAt(1)
        nav := Navigator(screen, SeederConfig(), clock, () => "", "", alive)
        Assert(!nav.GetIn(600))
        Assert(clock.at < 30)
    }

    static Test_refreshes_when_server_is_missing() {
        screen := FakeScreen(HappyPath())
        screen.Show("browser_refresh")
        nav := Navigator(screen, SeederConfig(), FakeClock(), () => "")
        Assert(!nav.GetIn(100))
        n := Count(screen.keys, "r")
        Assert(4 <= n && n <= 6, n " refreshes")  ; every ~20 s, not every tick
    }

    static Test_skips_when_pc_locked() {
        r := MakeRun()
        r.game.locked := true
        AssertEq(SeedWith(r.config, r.game, r.screen, Statuses([10]), r.clock), Runner.LOCKED)
        AssertEq(r.game.launches, 0)
    }

    static Test_does_not_relaunch_near_the_time_limit() {
        r := MakeRun()
        r.config.max_minutes := 20
        game := r.game
        each(n) {
            if n = 25  ; crash with ~7 minutes left, less than a relaunch needs
                game.isRunning := false
        }
        fetch := Counted(n => FakeStatus(20, 10, 10, "S"), each)
        AssertEq(SeedWith(r.config, r.game, r.screen, fetch, r.clock), Runner.TIMED_OUT)
        AssertEq(r.game.launches, 1)
        Assert(r.clock.at <= 20 * 60 + 60, "ran until " r.clock.at)
    }

    static Test_gave_up_watches_for_a_late_game_start() {
        r := MakeRun(false, false)
        SeedWith(r.config, r.game, r.screen, Statuses([10]), r.clock)
        AssertEq(r.game.lingered, 90)
    }

    static Test_stop_closes_the_game() {
        r := MakeRun()
        each(n) {
            if n = 4
                throw SeedStopped("Stopped")
        }
        fetch := Counted(n => FakeStatus(20, 10, 10, "S"), each)
        try
            SeedWith(r.config, r.game, r.screen, fetch, r.clock)
        catch SeedStopped
            stopped := true
        Assert(IsSet(stopped), "didn't stop")
        Assert(!r.game.isRunning)
    }

    static Test_gives_up_when_game_wont_start() {
        r := MakeRun(false, false)
        AssertEq(SeedWith(r.config, r.game, r.screen, Statuses([10]), r.clock), Runner.GAVE_UP)
        AssertEq(r.game.launches, r.config.max_restarts + 1)
    }

    static Test_gives_up_when_server_never_appears() {
        r := MakeRun()
        path := HappyPath()
        path["browser_search|enter"] := [["browser_search"], []]  ; search finds nothing
        r.screen.transitions := path
        AssertEq(SeedWith(r.config, r.game, r.screen, Statuses([10]), r.clock), Runner.GAVE_UP)
        Assert(!r.game.isRunning)
    }

    static Test_times_out_and_closes_game() {
        r := MakeRun()
        r.config.max_minutes := 10
        AssertEq(SeedWith(r.config, r.game, r.screen, Statuses([10]), r.clock), Runner.TIMED_OUT)
        Assert(!r.game.isRunning)
    }

    static Test_nudges_to_avoid_idle_kick() {
        r := MakeRun()
        SeedWith(r.config, r.game, r.screen, Statuses([10, 10, 10, 10, 10, 10, 10, 10, 80]), r.clock)
        Assert(Includes(r.screen.keys, "a") && Includes(r.screen.keys, "d"))
    }

    static Test_unknown_screen_is_logged_with_a_screenshot() {
        Logs.capture := []
        screen := FakeScreen(HappyPath())
        saved := []
        screen.DefineProp("SaveScreenshot", {Call: (this, path) => (saved.Push(path), FileAppend("png", path))})
        screen.Show("menu_enlist")
        screen.transitions := Map("menu_enlist", [["menu_enlist"], []])  ; leads to a screen we don't know
        nav := Navigator(screen, SeederConfig(), FakeClock(), () => "")
        Assert(!nav.GetIn(200))
        AssertEq(saved.Length, 1)
        SplitPath(saved[1], , &folder)
        AssertEq(folder, App.Dir "\debug")
        found := false
        for line in Logs.capture
            if InStr(line, "unrecognised screen")
                found := true
        Assert(found, "no log line about the screen")
    }

    static Test_debug_screenshots_are_capped_and_a_stuck_file_does_not_block_new_ones() {
        debug := App.Dir "\debug"
        DirCreate(debug)
        loop 25
            FileAppend("x", debug "\20260101-0000" Format("{:02d}", A_Index - 1) ".png")
        locked := debug "\20260101-000000.png"
        hold := FileOpen(locked, "r -rwd")  ; open elsewhere: can't be deleted
        screen := FakeScreen(HappyPath())
        screen.DefineProp("SaveScreenshot", {Call: (this, path) => FileAppend("new", path)})
        nav := Navigator(screen, SeederConfig(), FakeClock(), () => "")
        nav.Snapshot("test")
        hold.Close()
        files := []
        loop files debug "\*.png"
            files.Push(A_LoopFileName)
        Assert(FileExist(locked), "the file in use was deleted")
        AssertEq(files.Length, Flow.KEEP_SCREENSHOTS + 1)
        newOne := false
        loop files debug "\*.png"
            if FileRead(A_LoopFileFullPath) == "new"
                newOne := true
        Assert(newOne, "no new screenshot")
    }

    ; Staggered leaving: once seeded, each copy waits its own random time.

    static Test_waits_its_random_time_once_seeded_then_leaves() {
        r := MakeRun()
        w := Watch(r.game, r.clock, Statuses([10, 10, 40, 80]))
        AssertEq(SeedWith(r.config, r.game, r.screen, w.fetch, r.clock, () => 0.25), Runner.SEEDED)
        wait := 0.25 * r.config.leave_delay_minutes * 60
        took := w.closes[1] - LastReached(w.readings)
        Assert(wait <= took && took < wait + r.config.poll_seconds, "left after " took " s")
        AssertEq(w.closes.Length, 1)
        Assert(!r.game.isRunning)
        AssertEq(Count(r.screen.clicks, "create_unit_button"), 1)
    }

    static Test_copies_leave_at_different_times() {
        left := []
        for item in [0.1, 0.9] {
            fraction := item  ; a closure can't see a for loop's own variable
            r := MakeRun()
            w := Watch(r.game, r.clock, Statuses([10, 80]))
            SeedWith(r.config, r.game, r.screen, w.fetch, r.clock, () => fraction)
            left.Push(w.closes[1] - LastReached(w.readings))
        }
        config := SeederConfig()
        Assert(left[2] - left[1] >= 0.8 * config.leave_delay_minutes * 60 - config.poll_seconds)
    }

    static Test_default_wait_is_up_to_ten_minutes() {
        AssertEq(SeederConfig().leave_delay_minutes, 10)
        r := MakeRun()
        w := Watch(r.game, r.clock, Statuses([10, 80]))
        SeedWith(r.config, r.game, r.screen, w.fetch, r.clock, () => 0.999)
        took := w.closes[1] - LastReached(w.readings)
        Assert(9 * 60 < took && took < 10 * 60 + r.config.poll_seconds, "left after " took " s")
    }

    static Test_no_wait_when_the_delay_is_zero() {
        r := MakeRun()
        r.config.leave_delay_minutes := 0
        w := Watch(r.game, r.clock, Statuses([10, 10, 80]))
        AssertEq(SeedWith(r.config, r.game, r.screen, w.fetch, r.clock, () => 0.9), Runner.SEEDED)
        AssertEq(w.closes[1], LastReached(w.readings))
    }

    static Test_the_wait_starts_again_if_the_count_drops_back_under() {
        r := MakeRun()
        w := Watch(r.game, r.clock, Statuses([10, 80, 80, 79, 80]))
        AssertEq(SeedWith(r.config, r.game, r.screen, w.fetch, r.clock, () => 0.5), Runner.SEEDED)
        first80 := ""
        for reading in w.readings
            if reading[2] != "" && reading[2] >= 80 {
                first80 := reading[1]
                break
            }
        wait := 0.5 * r.config.leave_delay_minutes * 60
        Assert(w.closes[1] - LastReached(w.readings) >= wait)
        Assert(LastReached(w.readings) > first80)
    }

    static Test_no_new_squad_while_waiting_to_leave() {
        ; The map changes after the server is seeded: everyone is sent back to
        ; Units, but the seeder only waits out its time there and then leaves.
        r := MakeRun()
        screen := r.screen
        each(n) {
            if n = 5
                screen.Show("switch_team", "squad_join", "infantry_create")
        }
        fetch := Counted(n => FakeStatus(n >= 3 ? 80 : 20, 40, 40, "S"), each)
        AssertEq(SeedWith(r.config, r.game, r.screen, fetch, r.clock, () => 0.5), Runner.SEEDED)
        AssertEq(Count(r.screen.clicks, "infantry_create"), 1)
        Assert(!Includes(r.screen.clicks, "squad_join"))
        Assert(r.game.launches = 1 && !r.game.isRunning)
    }

    static Test_back_under_after_a_map_change_creates_a_new_squad() {
        ; Seeded, then players leave at the map change: it leads a new squad again.
        r := MakeRun()
        screen := r.screen
        each(n) {
            if n = 4
                screen.Show("switch_team", "squad_join", "infantry_create")
        }
        answer(n) {
            players := n = 3 || n >= 8 ? 80 : 70
            return FakeStatus(players, players // 2, players - players // 2, "S")
        }
        AssertEq(SeedWith(r.config, r.game, r.screen, Counted(answer, each), r.clock, () => 0.5), Runner.SEEDED)
        AssertEq(Count(r.screen.clicks, "create_unit_button"), 2)
        Assert(!Includes(r.screen.clicks, "squad_join"))
    }

    static Test_game_closing_while_waiting_counts_as_seeded() {
        r := MakeRun()
        game := r.game, screen := r.screen
        each(n) {
            if n = 4 {  ; crash, or the player closed it
                game.isRunning := false
                screen.Show()
            }
        }
        fetch := Counted(n => FakeStatus(n >= 3 ? 80 : 20, 40, 40, "S"), each)
        AssertEq(SeedWith(r.config, r.game, r.screen, fetch, r.clock, () => 0.5), Runner.SEEDED)
        AssertEq(r.game.launches, 1)
    }

    static Test_time_limit_while_waiting_counts_as_seeded() {
        r := MakeRun()
        r.config.leave_delay_minutes := 10 * r.config.max_minutes
        AssertEq(SeedWith(r.config, r.game, r.screen, Statuses([10, 80]), r.clock, () => 1.0), Runner.SEEDED)
        Assert(!r.game.isRunning)
        Assert(r.clock.at <= r.config.max_minutes * 60 + r.config.poll_seconds)
    }

    static Test_stop_hotkey_still_works_while_waiting() {
        r := MakeRun()
        readings := []
        config := r.config
        clock := FakeClock()
        stopSleep(this, seconds) {
            this.at += seconds
            if readings.Length && seconds = config.poll_seconds
                throw SeedStopped("Stopped")
        }
        clock.DefineProp("Sleep", {Call: stopSleep})
        counts := Statuses([10, 10, 80])
        fetch(url) {
            status := counts(url)
            if status.players >= 80
                readings.Push(status)
            return status
        }
        try
            SeedWith(r.config, r.game, r.screen, fetch, clock, () => 0.5)
        catch SeedStopped
            stopped := true
        Assert(IsSet(stopped), "didn't stop")
        AssertEq(readings.Length, 1)  ; stopped mid-wait
        Assert(!r.game.isRunning)  ; game closed
    }
}
