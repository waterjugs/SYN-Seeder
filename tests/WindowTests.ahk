; The setup window: what it shows and what its buttons do. Nothing real
; happens: the daily task, the run lock, starting a run and the game are faked.

class WindowTests {
    ; A hidden window on settings 06:35 / Epic, with the daily task scheduled.
    ; Returns {w, calls}; calls lists what it asked of the task, runs and game.
    static Make(config := "", scheduled := true, scale := "") {
        calls := []
        Patches.Set(DailyTask, "IsScheduled", (*) => scheduled)
        Patches.Set(DailyTask, "Schedule", (this, start) => calls.Push("schedule " start))
        Patches.Set(DailyTask, "Unschedule", (*) => calls.Push("unschedule"))
        Patches.Set(SetupWindow.Prototype, "StartRun", (*) => (calls.Push("seed"), 4242))
        Patches.Set(SetupWindow.Prototype, "Open", (this, url) => calls.Push("open " url))
        Patches.Set(SeedLock, "Running", (*) => false)
        Patches.Set(SeedLock, "Runs", (*) => [])
        Patches.Set(SeedLock, "HeldElsewhere", (*) => false)
        Patches.Set(SeedLock, "Alive", (*) => false)
        Patches.Set(SeedLock, "Find", (*) => 0)
        Patches.Set(SeedLock, "Owner", (this, hwnd) => hwnd + 1000)
        Patches.Set(HllGame.Prototype, "Running", (*) => false)
        Patches.Set(HllGame.Prototype, "Pid", (*) => 0)
        Patches.Set(HllGame.Prototype, "Close", (*) => calls.Push("close game"))
        Patches.Set(HllGame, "_End", (this, pid) => calls.Push("end game " pid))
        if config = "" {
            config := SeederConfig()
            config.start_time := "06:35", config.launcher := "epic"
        }
        return {w: SetupWindow(config, false, scale), calls: calls}
    }

    ; Throws, for fakes that fail.
    static Raise(message) {
        throw Error(message)
    }

    ; Runs ``test`` with a fresh window, and closes the window after.
    static With(test, config := "", scheduled := true) {
        made := WindowTests.Make(config, scheduled)
        try
            test(made.w, made.calls)
        finally
            made.w.Dispose()
    }

    static StatusOf(w) => w.statusLine.Text

    static Test_shows_settings() {
        WindowTests.With((w, calls) => (
            AssertEq([w.hour, w.minute, w.launcher], ["06", "35", "epic"]),
            Assert(w.enabled, "Seed automatically should be ticked"),
            Assert(InStr(WindowTests.StatusOf(w), "Seeds every day at 06:35.") = 1, WindowTests.StatusOf(w)),
            AssertEq(calls, [])))
    }

    static Test_not_scheduled_says_how() {
        WindowTests.With((w, calls) => (
            Assert(!w.enabled),
            AssertEq(WindowTests.StatusOf(w), "Not scheduled. Tick " Chr(0x201C) "Seed automatically" Chr(0x201D) " and Save.")), , false)
    }

    static Test_clock_says_am_or_pm() {
        check(w, calls) {
            AssertEq(w.clock.Text, "6:35 AM")
            for item in [["00", "12:35 AM"], ["12", "12:35 PM"], ["19", "7:35 PM"]] {
                w.hour := item[1]
                w.ShowClock()
                AssertEq(w.clock.Text, item[2])
            }
        }
        WindowTests.With(check)
    }

    static Test_odd_start_times_are_tidied() {
        for item in [["7:05", "07", "05"], ["07:07", "07", "00"], ["25:00", "07", "00"], ["soon", "07", "00"], ["23:55", "23", "55"]] {
            config := SeederConfig()
            config.start_time := item[1]
            want := [item[2], item[3]]
            WindowTests.With((w, calls) => AssertEq([w.hour, w.minute], want, config.start_time), config)
        }
    }

    static Test_server_count() {
        check(w, calls) {
            AssertEq(w.note, SetupWindow.CHECKING)
            w.ShowServer(37)
            AssertEq([w.count, w.NeedText()], [37, "Needs 43 more"])
            w.ShowServer(84)
            AssertEq(w.NeedText(), "Seeded")
            w.ShowServer("")
            AssertEq([w.count, w.note, w.NeedText()], ["", "Couldn't reach the server stats.", ""])
        }
        WindowTests.With(check)
    }

    static Test_threshold_label_stays_on_the_meter() {
        for threshold in [0, 80, 100, 150] {
            labelW := 75, w := 432
            tick := Round(3 + 426 * Min(Max(threshold, 0), 100) / 100)
            x := Paint.LabelX(tick, labelW, w)
            Assert(x >= 0 && x + labelW <= w, "threshold " threshold ": label at " x)
        }
        AssertEq(Paint.LabelX(216, 76, 432), 178)  ; centred on the tick when there's room
    }

    static Test_meter_is_drawn() {
        check(w, calls) {
            pic := Canvas(w.contentWidth, w.countLine + Look.Px(38), Look.TWILIGHT)
            Paint.Players(pic, w.fonts, 37, "", 80, 100, w.countLine)
            y := w.countLine + Look.Px(6) + Look.Px(7)
            AssertEq(Look.Hex(pic.Pixel(50, y)), Look.Hex(Look.FIRST_LIGHT), "filled part")
            AssertEq(Look.Hex(pic.Pixel(300, y)), Look.Hex(Look.TRACK), "empty part")
            AssertEq(Look.Hex(pic.Pixel(344, y)), Look.Hex(Look.HAZE), "tick at 80")
            Paint.Players(pic, w.fonts, 84, "", 80, 100, w.countLine)
            AssertEq(Look.Hex(pic.Pixel(300, y)), Look.Hex(Look.PADDY), "seeded")
        }
        WindowTests.With(check)
    }

    static Test_header_is_dusk_over_first_light() {
        Patches.Value(Look, "scale", 1.0)  ; the header's size at 100%, whatever this PC's scaling
        pic := Canvas(480, 92)
        Paint.Header(pic, Font("Tahoma", 0, 0, false, 36))
        AssertEq(Look.Hex(pic.Pixel(3, 0)), "0C1823", "night at the top")
        AssertEq(Look.Hex(pic.Pixel(3, 91)), Look.Hex(Look.FIRST_LIGHT), "first light at the bottom")
        AssertEq(SeedlingCheck.Problems(pic), [], "seedling")
    }

    static Test_seedling_check_sees_a_missing_stem() {
        Patches.Value(Look, "scale", 1.0)
        pic := Canvas(480, 92)
        Paint.Header(pic, Font("Tahoma", 0, 0, false, 36))
        sky := pic.Pixel(3, 46)
        s := Look.scale, u := Look.MARK_UNIT * s
        pic.Rect(0, Look.MARK_Y * s + 35 * u, 240, 21 * u, sky)  ; paints over the stem, as 1.0.0 left it
        problems := SeedlingCheck.Problems(pic)
        AssertEq(problems.Length, 1, JoinList(problems, "; "))
        Assert(InStr(problems[1], "no stem"), problems[1])
        pic.Rect(0, 0, 240, Look.MARK_Y * s + 35 * u, sky)  ; and over the leaves
        AssertEq(SeedlingCheck.Problems(pic).Length, 2)
    }

    static Test_seedling_check_sees_a_missing_leaf() {
        Patches.Value(Look, "scale", 1.0)
        s := Look.scale, u := Look.MARK_UNIT * s
        for side in ["left", "right"] {
            pic := Canvas(480, 92)
            Paint.Header(pic, Font("Tahoma", 0, 0, false, 36))
            x := SeedlingCheck.StemX(pic)
            Assert(x != "", "the stem")
            left := side = "left" ? 0 : Ceil(x + 2 * u)
            right := side = "left" ? Floor(x - 2 * u) : 240
            pic.Rect(left, 0, right - left, Look.MARK_Y * s + 35 * u, pic.Pixel(3, 20))  ; paints over one leaf
            problems := SeedlingCheck.Problems(pic)
            AssertEq(problems.Length, 1, JoinList(problems, "; "))
            Assert(InStr(problems[1], "the seedling's " side " leaf"), problems[1])
        }
    }

    static Test_player_count_is_fetched_without_waiting() {
        starts := []
        Patches.Set(Http, "Start", (this, url, accept := "", timeout := 0, async := false) => (starts.Push([url, async]), {}))
        Patches.Set(Http, "Done", (*) => true)
        Patches.Set(Http, "Check", (this, req) => req)
        Patches.Set(Http, "BodyText", (*) => '{"result": {"name": "x", "player_count": 12, "player_count_by_team": {"allied": 6, "axis": 6}}, "failed": false}')
        check(w, calls) {
            w.RefreshServer()
            AssertEq(starts, [[w.config.crcon_url, true]])
            w.PollServer()
            AssertEq([w.count, w.NeedText(), w.request], [12, "Needs 68 more", ""])
        }
        WindowTests.With(check)
    }

    static Test_slow_fetch_is_not_doubled_up() {
        starts := 0, done := false
        Patches.Set(Http, "Start", (*) => (starts++, {Abort: (*) => 0}))
        Patches.Set(Http, "Done", (*) => done)
        check(w, calls) {
            w.RefreshServer()
            w.RefreshServer()  ; 30 s later, still waiting on the stats site
            AssertEq(starts, 1)
            w.PollServer()
            AssertEq([w.count, w.note], ["", SetupWindow.CHECKING])
            w.requestAt -= SetupWindow.SERVER_TIMEOUT_MS  ; and now it's been too long
            w.PollServer()
            AssertEq([w.count, w.note, w.request], ["", SetupWindow.UNREACHABLE, ""])
            w.RefreshServer()
            AssertEq(starts, 2)
        }
        WindowTests.With(check)
    }

    static Test_unreachable_stats_say_so() {
        Patches.Set(Http, "Start", (*) => {})
        Patches.Set(Http, "Done", (*) => true)
        Patches.Set(Http, "Check", (*) => WindowTests.Raise("HTTP 502 Bad Gateway"))
        check(w, calls) {
            Logs.capture := []
            w.RefreshServer()
            w.PollServer()
            AssertEq([w.count, w.note], ["", SetupWindow.UNREACHABLE])
            Assert(InStr(Logs.capture[1], "502"), Logs.capture[1])
        }
        WindowTests.With(check)
    }

    static Test_save_writes_settings_and_schedules() {
        check(w, calls) {
            w.hour := "19", w.minute := "05", w.launcher := "steam"
            Assert(w.Save())
            saved := SeederConfig.Load()
            AssertEq([saved.start_time, saved.launcher], ["19:05", "steam"])
            AssertEq(calls, ["schedule 19:05"])
            Assert(InStr(WindowTests.StatusOf(w), "Saved. Seeds every day at 19:05.") = 1, WindowTests.StatusOf(w))
        }
        WindowTests.With(check)
    }

    static Test_save_without_automatic_seeding_unschedules() {
        check(w, calls) {
            w.ToggleAutomatic()
            Assert(!w.enabled)
            w.Save()
            AssertEq(calls, ["unschedule"])
        }
        WindowTests.With(check)
    }

    static Test_scheduling_error_is_shown() {
        check(w, calls) {
            Patches.Set(DailyTask, "Schedule", (*) => WindowTests.Raise("Access is denied."))
            Logs.capture := []
            Assert(!w.Save())
            AssertEq(WindowTests.StatusOf(w), "Couldn't set up the schedule: Access is denied.")
            AssertEq(w.statusColor, Look.FLARE)
        }
        WindowTests.With(check)
    }

    static Test_seed_now_saves_then_starts() {
        check(w, calls) {
            w.SeedNow()
            AssertEq(calls, ["schedule 06:35", "seed"])
            Assert(InStr(WindowTests.StatusOf(w), "Seeding started.") = 1, WindowTests.StatusOf(w))
            AssertEq([w.seeding, w.spawned], [true, 4242])
            AssertEq(A_IsCritical, 0, "Seed now left Critical on")
        }
        WindowTests.With(check)
    }

    ; Seed now runs Critical: a Stop seeding click that comes in meanwhile
    ; waits until the run has started, so it can stop it.
    static Test_seed_now_holds_other_clicks_until_the_run_has_started() {
        order := []
        check(w, calls) {
            click() => order.Push("click")
            start(*) {
                SetTimer(click, -1)  ; e.g. Stop seeding, clicked meanwhile
                Sleep(50)
                order.Push(A_IsCritical ? "started, critical" : "started")
                return 4242
            }
            Patches.Set(SetupWindow.Prototype, "StartRun", start)
            w.SeedNow()
            order.Push("returned")
            Sleep(50)
            AssertEq(order, ["started, critical", "returned", "click"])
        }
        WindowTests.With(check)
    }

    static Test_seed_now_starts_unless_the_count_says_seeded() {
        for item in [79, ""] {  ; below 80, or the stats site unreachable
            amount := item  ; nested functions can't see a for loop's variables
            check(w, calls) {
                w.ShowServer(amount)
                w.SeedNow()
                AssertEq(calls[calls.Length], "seed", "count " amount)
            }
            WindowTests.With(check)
        }
    }

    static Test_seed_now_when_the_server_is_already_seeded() {
        check(w, calls) {
            w.ShowServer(84)
            w.SeedNow()
            AssertEq(calls, ["schedule 06:35"])  ; settings saved, no run
            AssertEq(WindowTests.StatusOf(w), "The server is already seeded (84 players), so there's nothing to do.")
        }
        WindowTests.With(check)
    }

    static Test_seed_now_when_the_game_is_open() {
        check(w, calls) {
            Patches.Set(HllGame.Prototype, "Running", (*) => true)
            w.SeedNow()
            AssertEq(calls, ["schedule 06:35"])
            Assert(InStr(WindowTests.StatusOf(w), "The game is already open.") = 1, WindowTests.StatusOf(w))
        }
        WindowTests.With(check)
    }

    static Test_seed_now_when_already_seeding() {
        check(w, calls) {
            Patches.Set(SeedLock, "Running", (*) => true)
            w.SeedNow()
            AssertEq(calls, [])
            AssertEq(WindowTests.StatusOf(w), "Already seeding.")
        }
        WindowTests.With(check)
    }

    static Test_seed_now_when_the_run_wont_start() {
        check(w, calls) {
            Patches.Set(SetupWindow.Prototype, "StartRun", (*) => WindowTests.Raise("Couldn't copy SynSeeder.exe"))
            Logs.capture := []
            w.SeedNow()
            AssertEq(WindowTests.StatusOf(w), "Couldn't start seeding: Couldn't copy SynSeeder.exe")
            AssertEq([w.statusColor, w.spawned, w.seeding], [Look.FLARE, 0, ""])
        }
        WindowTests.With(check)
    }

    static Test_stop_with_nothing_running() {
        check(w, calls) {
            w.StopSeeding()
            AssertEq(WindowTests.StatusOf(w), "Nothing is seeding right now.")
            AssertEq(calls, [])
        }
        WindowTests.With(check)
    }

    ; Fakes runs for Stop seeding: ``rounds`` lists the run windows found at
    ; each look. Records what was asked, waited on and ended in ``log``.
    static FakeRuns(rounds, log, stopsBy := true) {
        looks := 0
        Patches.Set(SeedLock, "Runs", (*) => (looks++, looks <= rounds.Length ? rounds[looks] : []))
        Patches.Set(SeedLock, "Ask", (this, hwnd) => (log.Push("ask " hwnd), SeedLock.Owner(hwnd)))
        Patches.Set(SeedLock, "WaitEnd", (this, pid, seconds) => (log.Push("wait " pid), stopsBy))
        Patches.Set(SeedLock, "End", (this, pid) => log.Push("end " pid))
    }

    static Test_stop_asks_the_run_then_closes_the_game() {
        log := []
        check(w, calls) {
            WindowTests.FakeRuns([[7]], log)
            Logs.capture := []
            w.StopSeeding()
            AssertEq(log, ["ask 7", "wait 1007"])
            AssertEq(calls, ["close game"])
            AssertEq(WindowTests.StatusOf(w), "Stopped seeding and closed the game.")
        }
        WindowTests.With(check)
    }

    static Test_stop_ends_a_run_that_wont_stop() {
        log := []
        check(w, calls) {
            WindowTests.FakeRuns([[7]], log, false)
            Logs.capture := []
            w.StopSeeding()
            AssertEq(log, ["ask 7", "wait 1007", "end 1007"])
            AssertEq(calls, ["close game"])
        }
        WindowTests.With(check)
    }

    static Test_stop_catches_a_run_handing_over_to_a_new_version() {
        log := []
        check(w, calls) {
            WindowTests.FakeRuns([[7], [8]], log)
            Logs.capture := []
            w.StopSeeding()
            AssertEq(log, ["ask 7", "wait 1007", "ask 8", "wait 1008"])
        }
        WindowTests.With(check)
    }

    static Test_stop_waits_for_a_run_that_is_starting() {
        log := [], held := 0
        check(w, calls) {
            WindowTests.FakeRuns([[], [9]], log)  ; holds the lock, names its window a moment later
            Patches.Set(SeedLock, "HeldElsewhere", (*) => (held++, !Includes(log, "ask 9")))
            Logs.capture := []
            w.StopSeeding()
            AssertEq(log, ["ask 9", "wait 1009"])
            Assert(held >= 1)
        }
        WindowTests.With(check)
    }

    ; A run Seed now started that hasn't named its window yet can't be asked
    ; to stop, so it gets START_GRACE_MS to; one that hasn't by then is ended
    ; before it can start the game.
    static Test_stop_ends_the_run_seed_now_started_if_its_window_isnt_up() {
        log := []
        check(w, calls) {
            WindowTests.FakeRuns([], log)
            Patches.Value(SetupWindow, "START_GRACE_MS", 300)
            Patches.Set(SeedLock, "Alive", (this, pid) => pid = 4242 && !Includes(log, "end 4242"))
            w.SeedNow()
            Logs.capture := []
            t0 := A_TickCount
            w.StopSeeding()
            AssertEq(log, ["end 4242", "wait 4242"])
            Assert(A_TickCount - t0 >= 300, "didn't give it time to name its window")
            AssertEq(calls, ["schedule 06:35", "seed", "close game"])
            AssertEq(WindowTests.StatusOf(w), "Stopped seeding and closed the game.")
        }
        WindowTests.With(check)
    }

    static Test_stop_asks_the_run_seed_now_started_once_its_window_is_up() {
        log := []
        check(w, calls) {
            WindowTests.FakeRuns([[], [], [3242]], log)  ; names its window on the third look
            Patches.Value(SetupWindow, "START_GRACE_MS", 5000)
            Patches.Set(SeedLock, "Alive", (this, pid) => pid = 4242 && !Includes(log, "wait 4242"))
            w.SeedNow()
            Logs.capture := []
            w.StopSeeding()
            AssertEq(log, ["ask 3242", "wait 4242"])
            AssertEq(WindowTests.StatusOf(w), "Stopped seeding and closed the game.")
        }
        WindowTests.With(check)
    }

    static Test_stop_lets_the_run_seed_now_started_end_by_itself() {
        log := []
        check(w, calls) {
            WindowTests.FakeRuns([], log)
            Patches.Value(SetupWindow, "START_GRACE_MS", 5000)
            alive := 3  ; e.g. it found another run going, and exits
            Patches.Set(SeedLock, "Alive", (this, pid) => pid = 4242 && alive-- > 0)
            w.SeedNow()
            Logs.capture := []
            w.StopSeeding()
            AssertEq(log, [])
            AssertEq(WindowTests.StatusOf(w), "Nothing is seeding right now.")
        }
        WindowTests.With(check)
    }

    ; SynSeeder-update.exe only ever runs as a run's new version.
    static Test_stop_ends_a_new_version_taking_over_a_run() {
        log := []
        check(w, calls) {
            WindowTests.FakeRuns([], log)
            found := [5555, 5555]  ; it's still there after the first try
            Patches.Set(SeedLock, "Find", (this, name) => (log.Push("find " name), found.Length ? found.RemoveAt(1) : 0))
            Logs.capture := []
            w.StopSeeding()
            AssertEq(log, ["find " Updater.UPDATE_NAME, "end 5555", "wait 5555", "find " Updater.UPDATE_NAME])
            AssertEq(calls, ["close game"])
            AssertEq(WindowTests.StatusOf(w), "Stopped seeding and closed the game.")
        }
        WindowTests.With(check)
    }

    ; A run that had to be ended can't close a game its launcher starts late,
    ; so the window watches for one for a while. Seed now stops watching.
    static Test_after_ending_a_run_the_window_closes_a_game_that_starts_late() {
        log := [], pid := 0
        check(w, calls) {
            WindowTests.FakeRuns([[7]], log, false)
            Patches.Set(HllGame.Prototype, "Pid", (*) => pid)
            Logs.capture := []
            w.StopSeeding()
            AssertEq(log, ["ask 7", "wait 1007", "end 1007"])
            Assert(InStr(WindowTests.StatusOf(w), "Stopped seeding and closed the game. If the launcher still starts the game") = 1, WindowTests.StatusOf(w))
            Assert(w.lateWatch, "not watching for a late game")
            w.lateWatch.Call()  ; the timer, before the game is up
            AssertEq(calls, ["close game"])
            pid := 8080
            w.lateWatch.Call()
            AssertEq(calls, ["close game", "end game 8080"])
            AssertEq(w.lateWatch, "", "still watching")
            w.WatchLateGame(60)
            w.SeedNow()
            AssertEq(w.lateWatch, "", "Seed now didn't stop the watch")
        }
        WindowTests.With(check)
    }

    ; A run that starts during the watch (the schedule, Seed now in another
    ; window) owns the game, so the watch ends and leaves the game alone.
    static Test_the_late_game_watch_leaves_a_new_runs_game_alone() {
        log := []
        check(w, calls) {
            WindowTests.FakeRuns([[7]], log, false)
            Patches.Set(HllGame.Prototype, "Pid", (*) => 8080)
            Logs.capture := []
            w.StopSeeding()
            Assert(w.lateWatch, "not watching for a late game")
            Patches.Set(SeedLock, "Running", (*) => true)
            w.lateWatch.Call()
            AssertEq(calls, ["close game"])
            AssertEq(w.lateWatch, "")
        }
        WindowTests.With(check)
    }

    ; Seed now ends the watch only once it has started a run, whose game it then is.
    static Test_seed_now_keeps_watching_for_a_late_game_unless_it_starts_a_run() {
        check(w, calls) {
            w.WatchLateGame(60)
            w.ShowServer(84)  ; seeded: nothing to start
            w.SeedNow()
            Assert(w.lateWatch, "stopped watching, though no run started")
            w.ShowServer(20)
            Patches.Set(SetupWindow.Prototype, "StartRun", (*) => WindowTests.Raise("no such file"))
            w.SeedNow()
            Assert(w.lateWatch, "stopped watching, though the run couldn't start")
            Patches.Set(SetupWindow.Prototype, "StartRun", (*) => 4242)
            w.SeedNow()
            AssertEq(w.lateWatch, "")
        }
        WindowTests.With(check)
    }

    ; Closing the window during the watch hides it, and SynSeeder exits once
    ; the watch is over.
    static Test_closing_the_window_keeps_watching_for_a_late_game() {
        log := [], pid := 0, exits := 0
        check(w, calls) {
            w.DefineProp("Exit", {Call: (*) => exits++})
            WindowTests.FakeRuns([[7]], log, false)
            Patches.Set(HllGame.Prototype, "Pid", (*) => pid)
            Logs.capture := []
            w.StopSeeding()
            Assert(w.lateWatch, "not watching for a late game")
            w.Close()
            AssertEq(exits, 0, "exited while it should still be watching")
            Assert(w.lateWatch, "closing the window stopped the watch")
            pid := 8080
            w.lateWatch.Call()
            AssertEq(calls, ["close game", "end game 8080"])
            AssertEq(exits, 1)
        }
        WindowTests.With(check)
    }

    static Test_closing_the_window_exits() {
        exits := 0
        check(w, calls) {
            w.DefineProp("Exit", {Call: (*) => exits++})
            w.Close()
            AssertEq(exits, 1)
        }
        WindowTests.With(check)
    }

    static Test_a_run_that_stops_by_itself_needs_no_watch() {
        log := []
        check(w, calls) {
            WindowTests.FakeRuns([[7]], log)
            Logs.capture := []
            w.StopSeeding()
            AssertEq(w.lateWatch, "")
        }
        WindowTests.With(check)
    }

    static Test_status_says_when_a_run_starts_and_ends_by_itself() {
        check(w, calls) {
            start := WindowTests.StatusOf(w)
            w.ShowSeeding(false)  ; first look, nothing running
            AssertEq(WindowTests.StatusOf(w), start)
            w.ShowSeeding(true)   ; e.g. the schedule started one
            Assert(InStr(WindowTests.StatusOf(w), "Seeding now.") = 1, WindowTests.StatusOf(w))
            w.ShowSeeding(false)  ; Ctrl+Alt+End, seeded, or the time limit
            AssertEq(WindowTests.StatusOf(w), "The run has ended.")
        }
        WindowTests.With(check)
    }

    static Test_status_after_seed_now_ends_when_the_run_does() {
        alive := true
        check(w, calls) {
            Patches.Set(SeedLock, "Alive", (this, pid) => pid = 4242 && alive)
            w.SeedNow()
            w.WatchSeed()  ; starting up: no lock yet, but its process is there
            Assert(InStr(WindowTests.StatusOf(w), "Seeding started.") = 1, WindowTests.StatusOf(w))
            Patches.Set(SeedLock, "Running", (*) => true)
            w.WatchSeed()
            Assert(InStr(WindowTests.StatusOf(w), "Seeding started.") = 1, "no change while it runs")
            Patches.Set(SeedLock, "Running", (*) => false)
            alive := false
            w.WatchSeed()
            AssertEq(WindowTests.StatusOf(w), "The run has ended.")
            AssertEq(w.spawned, 0)
        }
        WindowTests.With(check)
    }

    static Test_stop_message_stays() {
        log := []
        check(w, calls) {
            w.ShowSeeding(true)
            WindowTests.FakeRuns([[7]], log)
            Logs.capture := []
            w.StopSeeding()
            w.WatchSeed()
            AssertEq(WindowTests.StatusOf(w), "Stopped seeding and closed the game.")
        }
        WindowTests.With(check)
    }

    static Test_launcher_chips_and_automatic_box() {
        check(w, calls) {
            w.ChooseLauncher("steam")
            AssertEq(w.launcher, "steam")
            w.ToggleAutomatic(), w.ToggleAutomatic()
            Assert(w.enabled)
            w.Save()
            AssertEq(SeederConfig.Load().launcher, "steam")
        }
        WindowTests.With(check)
    }

    static Test_time_grid_picks_a_value() {
        check(w, calls) {
            w.OpenPicker("minute")
            AssertEq([w.picker.which, w.picker.chosen, w.picker.values.Length], ["minute", 8, 12])
            w.Pick(4)
            AssertEq([w.minute, w.clock.Text, w.picker], ["15", "6:15 AM", ""])
            AssertEq(w.minuteField.Text, "15")
        }
        WindowTests.With(check)
    }

    static Test_time_grid_keys() {
        check(w, calls) {
            w.OpenPicker("hour")
            AssertEq(w.picker.hot, 7)  ; "06"
            pop := w.picker.gui.Hwnd
            for key in [0x27, 0x28, 0x28, 0x28, 0x28, 0x25]  ; right, down x4 (stops at the last row), left
                w._Key(key, 0, 0x100, pop)
            AssertEq(w.picker.hot, 19)  ; "18"
            AssertEq(w._Key(0x41, 0, 0x100, pop), "", "other keys pass through")
            w._Key(0x0D, 0, 0x100, pop)
            AssertEq([w.hour, w.clock.Text, w.picker], ["18", "6:35 PM", ""])
            w.OpenPicker("hour")
            w._Key(0x1B, 0, 0x100, w.picker.gui.Hwnd)
            AssertEq([w.hour, w.picker], ["18", ""])
        }
        WindowTests.With(check)
    }

    static Test_time_grid_cells() {
        check(w, calls) {
            w.OpenPicker("hour")
            inset := Look.Px(4), cw := Look.Px(44), ch := Look.Px(30)
            AssertEq(w._CellAt(inset + 1, inset + 1), 1)
            AssertEq(w._CellAt(inset + 5 * cw + 2, inset + 3 * ch + 2), 24)
            AssertEq(w._CellAt(inset + 6 * cw + 2, inset + 1), 0)  ; right of the grid
            AssertEq(w._CellAt(0, 0), 0)                            ; the border
        }
        WindowTests.With(check)
    }

    static Test_clicking_the_open_picker_closes_it() {
        check(w, calls) {
            w.OpenPicker("minute")
            w.OpenPicker("minute")  ; the keyboard's Space on the picker again
            AssertEq(w.picker, "")
            w.OpenPicker("minute")
            w._ClickedAway(w.picker)  ; the mouse clicks the picker: the grid loses focus first
            AssertEq(w.picker, "")
            w.OpenPicker("minute")  ; then the click lands on the picker
            AssertEq(w.picker, "")
            w.OpenPicker("hour")    ; the other one opens
            AssertEq(w.picker.which, "hour")
        }
        WindowTests.With(check)
    }

    ; The grid opens on the monitor its picker is on: below the picker, or
    ; above it when there's no room below, and never off that monitor's edge.
    static Test_time_grid_stays_on_its_pickers_monitor() {
        check(w, calls) {
            w.hourField.GetPos(&fx, &fy, &fw, &fh)
            WinGetClientPos(&cx, &cy, , , w.gui)
            top := cy + fy, bottom := cy + fy + fh, right := cx + fx + fw
            gap := Look.Px(4), gridW := 2 * gap + 6 * Look.Px(44), gridH := 2 * gap + 4 * Look.Px(30)
            asked := []
            place(area) {
                Patches.Set(SetupWindow, "WorkAreaAt", (this, l, t, r, b) => (asked.Push([l, t, r, b]), area))
                w.OpenPicker("hour")
                WinGetPos(&x, &y, &gw, &gh, w.picker.gui)
                w.ClosePicker()
                AssertEq([gw, gh], [gridW, gridH], "grid size")
                return [x, y]
            }
            ; a monitor with room below
            AssertEq(place({left: cx - 2000, top: cy - 2000, right: cx + 2000, bottom: cy + 2000}), [right - gridW, bottom + gap])
            AssertEq(asked[1], [cx + fx, top, right, bottom], "the picker's own rectangle")
            ; one that ends just under the picker: above it
            AssertEq(place({left: cx - 2000, top: cy - 2000, right: cx + 2000, bottom: bottom + 10}), [right - gridW, top - gap - gridH])
            ; a monitor to the left whose right edge cuts through the grid: moved onto it
            AssertEq(place({left: right - gridW - 3000, top: cy - 2000, right: right - 20, bottom: cy + 2000}), [right - 20 - gridW, bottom + gap])
            ; and one whose left edge does
            AssertEq(place({left: right - 10, top: cy - 2000, right: right + 3000, bottom: cy + 2000}), [right - 10, bottom + gap])
        }
        WindowTests.With(check)
    }

    static Test_work_area_is_the_monitors() {
        MonitorGetWorkArea(MonitorGetPrimary(), &l, &t, &r, &b)
        area := SetupWindow.WorkAreaAt(l + 10, t + 10, l + 50, t + 30)
        AssertEq([area.left, area.top, area.right, area.bottom], [l, t, r, b])
        area := SetupWindow.WorkAreaAt(r + 50000, b + 50000, r + 50040, b + 50020)  ; nowhere: the nearest monitor
        Assert(area.right > area.left && area.bottom > area.top, "no area")
    }

    ; A message longer than two lines makes the status line taller, moving
    ; what's under it down and growing the window; a short one shrinks it back.
    static Test_long_status_grows_the_window() {
        check(w, calls) {
            terms := ""
            for ctrl in w.gui
                if ctrl.Type = "Text" && ctrl.Text == "Terms of Service"
                    terms := ctrl
            height := w.height
            w.statusLine.GetPos(, &top, , &lineH)
            terms.GetPos(, &termsY)
            long := "Couldn't set up the schedule:"
            loop 8
                long .= " Windows said something long about why it couldn't, number " A_Index "."
            w.Status(long, Look.FLARE)
            w.statusLine.GetPos(, &top2, , &lineH2)
            terms.GetPos(, &termsY2)
            grew := lineH2 - lineH
            Assert(grew > 0, "the status line didn't grow")
            Assert(lineH2 >= SetupWindow.TextHeight(w.statusLine, long, w.statusW), "the message doesn't fit")
            AssertEq([top2, termsY2 - termsY, w.height - height], [top, grew, grew])
            for ctrl in w.gui {
                ctrl.GetPos(&x, &y, &cw, &ch)
                Assert(y + ch <= w.height, ctrl.Type " '" ctrl.Text "' is below the window")
            }
            w.Status("Saved.")
            w.statusLine.GetPos(, , , &lineH3)
            terms.GetPos(, &termsY3)
            AssertEq([lineH3, termsY3, w.height], [lineH, termsY, height])
        }
        WindowTests.With(check)
    }

    ; Windows doesn't size a minimized window the way it restores it, so a
    ; status that changes then is fitted once the window is restored.
    static Test_status_change_while_minimized_fits_the_restored_window() {
        check(w, calls) {
            inner() {
                rect := Buffer(16, 0)
                DllCall("GetClientRect", "Ptr", w.gui.Hwnd, "Ptr", rect)
                return NumGet(rect, 12, "Int")
            }
            long := "Couldn't set up the schedule:"
            loop 4
                long .= " Windows said something long about why it couldn't, number " A_Index "."
            w.Show()
            w.Status(long, Look.FLARE)
            AssertEq(inner(), w.height, "the window didn't grow")
            WinMinimize(w.gui)
            Sleep(100)
            w.Status("The run has ended.")
            WinRestore(w.gui)
            Sleep(100)
            AssertEq(inner(), w.height, "the restored window isn't its new height")
        }
        WindowTests.With(check)
    }

    static Test_footer_links_open_the_terms_and_privacy_policy() {
        check(w, calls) {
            for text in ["Terms of Service", "Privacy Policy"] {
                for ctrl in w.gui
                    if ctrl.Type = "Text" && ctrl.Text == text
                        DllCall("SendMessageW", "Ptr", w.gui.Hwnd, "UInt", 0x111, "Ptr", DllCall("GetDlgCtrlID", "Ptr", ctrl.Hwnd, "Int"), "Ptr", ctrl.Hwnd)  ; WM_COMMAND, STN_CLICKED
            }
            Sleep(50)  ; the click events run as their own threads
            AssertEq(calls, ["open " App.TERMS_URL, "open " App.PRIVACY_URL])
        }
        WindowTests.With(check)
    }

    static Test_layout_at_any_scaling() {
        for scale in [1, 1.25, 1.5, 2] {
            made := WindowTests.Make(, , scale)
            w := made.w
            try {
                AssertEq(w.width, Round(480 * scale), "width at " scale)
                right := 0
                for ctrl in w.gui {
                    ctrl.GetPos(&x, &y, &cw, &ch)
                    Assert(x >= 0 && x + cw <= w.width && y >= 0 && y + ch <= w.height, ctrl.Type " '" ctrl.Text "' is outside the window at " scale)
                }
                w.clock.GetPos(&cx, , &cw)
                w.hourField.GetPos(&hx)
                Assert(cx + cw <= hx, "clock overlaps the hour picker at " scale)
                w.steamChip.GetPos(&sx, , &sw)
                w.epicChip.GetPos(&ex)
                Assert(sx + sw < ex, "chips overlap at " scale)
            } finally {
                w.Dispose()
                Look.scale := 1
            }
            Patches.Undo()
        }
    }

    static Test_font_checksums() {
        folder := A_ScriptDir "\..\assets\fonts"
        names := []
        loop files folder "\*.ttf"
            names.Push(A_LoopFileName)
        AssertEq(names.Length, FontFiles.SHA256.Count, "assets\fonts vs FontFiles.SHA256")
        for fileName in names {
            Assert(FontFiles.SHA256.Has(fileName), fileName " isn't in src\FontFiles.ahk")
            AssertEq(Sha256.File(folder "\" fileName), FontFiles.SHA256[fileName], fileName)
        }
    }

    static Test_colour_helpers() {
        AssertEq(Look.ColorRef(0x123456), 0x563412)
        AssertEq(Look.Mix(0x000000, 0xFFFFFF, 0.5), 0x808080)
        AssertEq(Look.Along(Look.DUSK, 0), 0x0C1823)
        AssertEq(Look.Along(Look.DUSK, 1), 0x4B3546)
        Assert(Abs(Look.NormalCdf(0) - 0.5) < 1e-6 && Abs(Look.NormalCdf(1.96) - 0.975) < 1e-3)
    }
}
