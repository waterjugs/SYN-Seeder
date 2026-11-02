; The seeding run: launch, join, stay in, leave once the server is full.
;
; Leaving is staggered: once the server reaches the seeded count, each copy
; waits its own random time (up to leave_delay_minutes) before closing the
; game, so seeders don't all drop off within the same half minute and pull
; the server back under the count.

class Runner {
    ; How a run ended.
    static ALREADY_SEEDED := "server was already seeded"
    static SEEDED := "server is seeded"
    static SERVER_DOWN := "server status unavailable"
    static GAME_IN_USE := "game was already running, left it alone"
    static LOCKED := "PC is locked; seeding needs you signed in and unlocked"
    static GAVE_UP := "couldn't get into the server"
    static TIMED_OUT := "hit the time limit"

    ; The server's status, asking up to ``tries`` times 10 s apart; "" if it never answered.
    static Status(fetch, url, clock, tries := 3) {
        loop tries {
            status := fetch(url)
            if status
                return status
            if A_Index < tries
                clock.Sleep(10)
        }
        return ""
    }

    ; This run's share of leave_delay_minutes, from 0 to 1.
    static LeaveFraction() => Random(0.0, 1.0)

    ; Seeds once. ``fetch`` reads the server's status from a URL (ServerStats.Fetch);
    ; ``rng`` gives a number from 0 to 1 that picks this run's wait before
    ; leaving. Returns one of the outcomes above; throws SeedStopped when stopped.
    static Seed(config, game, screen, fetch, clock, rng := "") {
        status := Runner.Status(fetch, config.crcon_url, clock)
        if !status
            return Runner.SERVER_DOWN
        Logs.Info(config.server_name " has " status.players " players (allies " status.allied ", axis " status.axis ")")
        if status.players >= config.seeded_threshold
            return Runner.ALREADY_SEEDED
        if game.Running()  ; someone is playing; don't take over their game
            return Runner.GAME_IN_USE
        if !game.Unlocked()
            return Runner.LOCKED

        latest := {status: status, at: clock.Now()}
        refreshStatus(maxAge := 0) {
            if clock.Now() - latest.at >= maxAge {
                fresh := fetch(config.crcon_url)
                if fresh
                    latest.status := fresh
                latest.at := clock.Now()
            }
        }
        needySide() {
            s := latest.status
            return Abs(s.allied - s.axis) >= 2 ? ServerStats.WeakerSide(s) : ""
        }
        pickSide() {
            ; Select Force can come minutes after the last check; use current numbers.
            refreshStatus(30)
            return ServerStats.WeakerSide(latest.status)
        }

        nav := Navigator(screen, config, clock, needySide, ObjBindMethod(game, "Focus"),
            ObjBindMethod(game, "Running"), pickSide, ObjBindMethod(game, "WaitingForUser"))
        deadline := clock.Now() + config.max_minutes * 60
        stayAfterSeeded := Max(config.leave_delay_minutes, 0) * 60 * (rng ? rng() : Runner.LeaveFraction())
        seededSince := ""  ; when the count last reached the seeded count
        attempts := 0
        inServer := false
        lastNudge := clock.Now()
        outcome := ""
        try {
            loop {
                remaining := deadline - clock.Now()
                if !inServer {
                    ; The first try always runs (its waits are cut to fit); a retry
                    ; needs time for a full launch and join.
                    if remaining <= 0 || (attempts && remaining < config.launch_timeout + config.load_timeout) {
                        outcome := Runner.TIMED_OUT
                        return outcome
                    }
                    if attempts > config.max_restarts {
                        outcome := Runner.GAVE_UP
                        return outcome
                    }
                    if attempts
                        refreshStatus()
                    attempts++
                    inServer := Runner._GetIn(config, game, nav, clock, deadline)
                    if !inServer {
                        game.Close()
                        clock.Sleep(15)
                        continue
                    }
                    lastNudge := clock.Now()
                }
                if remaining <= 0 {
                    outcome := seededSince != "" ? Runner.SEEDED : Runner.TIMED_OUT
                    return outcome
                }

                clock.Sleep(config.poll_seconds)
                if !game.Running() {
                    if seededSince != "" {
                        Logs.Warning("The game closed while waiting to leave; the server is seeded")
                        outcome := Runner.SEEDED
                        return outcome
                    }
                    Logs.Warning("The game closed or crashed; restarting")
                    inServer := false
                    continue
                }

                refreshStatus()
                count := latest.status.players
                Logs.Info("Players: " count "/" config.seeded_threshold)
                if count >= config.seeded_threshold {
                    if seededSince = "" {
                        seededSince := clock.Now()
                        if stayAfterSeeded >= config.poll_seconds
                            Logs.Info("Seeded. Leaving in about " MinutesText(stayAfterSeeded)
                                . ", so seeders don't all leave at once")
                    }
                    if clock.Now() - seededSince >= stayAfterSeeded {
                        outcome := Runner.SEEDED
                        return outcome
                    }
                } else if seededSince != "" {
                    Logs.Info("Back under " config.seeded_threshold " players; staying")
                    seededSince := ""
                }

                if !game.Focus()
                    continue  ; someone else has the screen; send nothing
                name := Flow.CurrentScreen(screen)
                if name == Flow.NO_SCREEN
                    continue  ; couldn't see the screen; look again next time
                if Flow.IsOverlay(name) {
                    nav.Handle(name)
                } else if name != "" {
                    ; Seeded and about to leave: no new squad, just stay connected.
                    if seededSince = "" {
                        ; Kicked to the menu, new map, or died: walk back in.
                        Logs.Info("Not in game any more; getting back in")
                        inServer := nav.GetIn(Min(config.load_timeout, Max(deadline - clock.Now(), 1)), false, deadline)
                    }
                } else if clock.Now() - lastNudge >= config.anti_afk_seconds {
                    Flow.Nudge(screen)
                    lastNudge := clock.Now()
                }
            }
        } finally {
            ; Steam can start the game minutes late (e.g. after an update), so
            ; if it isn't up at the end, keep watching for it a little longer.
            lateStart := outcome == Runner.GAVE_UP || (outcome == Runner.TIMED_OUT && attempts && !game.Running())
            if outcome == "" && game.launchPending  ; stopped soon after a launch timed out
                game.CloseLateStart(HllGame.LATE_START_SECONDS)
            else
                game.Close(lateStart ? 90 : 0)
        }
    }

    static _GetIn(config, game, nav, clock, deadline) {
        fresh := !game.Running()
        if fresh && !game.Launch(Min(config.launch_timeout, Max(deadline - clock.Now(), 1)))
            return false
        left := Max(deadline - clock.Now(), 1)  ; what the launch didn't use
        return nav.GetIn(Min(config.launch_timeout + config.load_timeout, left), fresh, deadline)
    }
}
