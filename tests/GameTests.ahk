; Finding, starting and focusing the game (ported from the first SynSeeder's
; tests/test_game.py and tests/test_launch.py).

; Swaps WinApi's window calls for ones that record what they were asked.
; ``front`` is the window in front: by default 5678, another program's.
; The game's window is 1234 (see GameWithWindow) and 4321 is another of its
; windows; 7777 and 7778 are SynSeeder's (this program runs as SynSeeder.exe).
; ``restoring`` is the game in front but still restoring from minimised.
FakeWinApi() {
    api := {polite: false, forced: true, idle: 0.0, calls: [], target: "", frontPid: 0, restoring: false, unlocked: true,
        front: 5678, pids: Map(1234, 100, 4321, 100, 5678, 200, 7777, 300, 7778, 301, 7779, 302),
        names: Map(100, "HLLVietnam-Win64-Shipping.exe", 200, "chrome.exe", 300, "SynSeeder.exe",
            301, "SynSeeder (1).exe", 302, "SynSeederish.exe", 400, "SynSeeder.exe")}
    Patches.Set(WinApi, "ForegroundWindow", (*) => api.front)
    Patches.Set(WinApi, "WindowPid", (this, hwnd) => api.pids.Has(hwnd) ? api.pids[hwnd] : 0)
    Patches.Set(WinApi, "ProcessName", (this, pid) => api.names.Has(pid) ? api.names[pid] : "")
    Patches.Set(WinApi, "OwnPid", (*) => 400)
    Patches.Set(WinApi, "DesktopUnlocked", (*) => api.unlocked)
    Patches.Set(WinApi, "ForegroundPid", (*) => api.frontPid)
    Patches.Set(WinApi, "InFront", (this, hwnd) => api.restoring)
    Patches.Set(WinApi, "SetInputTarget", (this, hwnd) => api.target := hwnd)
    Patches.Set(WinApi, "BringToFront", (this, hwnd) => (api.calls.Push("ask"), api.polite))
    Patches.Set(WinApi, "ForceToFront", (this, hwnd, altTap := true) => (api.calls.Push(altTap ? "force+alt" : "force"), api.forced))
    Patches.Set(WinApi, "UserIdleSeconds", (*) => api.idle)
    Patches.Set(WinApi, "Flash", (this, hwnd) => api.calls.Push("flash"))
    return api
}

; A game whose window is 1234.
GameWithWindow(config := "") {
    game := HllGame(config ? config : SeederConfig(), FakeClock())
    game.DefineProp("Window", {Call: (*) => 1234})
    return game
}

LogsWith(text) {
    n := 0
    for line in Logs.capture
        if InStr(line, text)
            n++
    return n
}

HLLV := "3b51901c38644473a9cba942253b3a41:cc1ab2f4d934407c8f1e6463d9c1dbdf:d7361b7d6fa94097bcadeac4b1f785fb"

; What the Epic launcher listed on the test PC before HLL Vietnam was installed.
Fortnite() => [
    Map("InstallLocation", "X:\Epic Games\Fortnite", "NamespaceId", "fn", "ItemId", "b619cf61a4144d67bd753dc990637e7c",
        "ArtifactId", "94bc5ec13f8f438c97fdbef3e9019e27", "AppName", "94bc5ec13f8f438c97fdbef3e9019e27"),
    Map("InstallLocation", "X:\Epic Games\Fortnite", "NamespaceId", "fn", "ItemId", "4fe75bbc5a674f4f9b356b5c90567da5",
        "ArtifactId", "Fortnite", "AppName", "Fortnite")]

Vietnam(folder := "X:\Epic Games\Hell_Let_Loose_Vietnam", app := "d7361b7d6fa94097bcadeac4b1f785fb") => Map(
    "InstallLocation", folder, "NamespaceId", "3b51901c38644473a9cba942253b3a41",
    "ItemId", "cc1ab2f4d934407c8f1e6463d9c1dbdf", "ArtifactId", app, "AppName", app)

; ``list`` with ``items`` added at the end, as a new Array.
Plus(list, items*) {
    out := list.Clone()
    out.Push(items*)
    return out
}

; Writes an Epic install list the way the launcher does (tabs and a byte-order mark).
Installed(entries) {
    path := App.Dir "\LauncherInstalled.dat"
    try FileDelete(path)
    FileAppend(Json.Dump(Map("InstallationList", entries), "`t"), path, "UTF-8")
    return path
}

class GameTests {
    static Test_in_front_when_windows_allows_it() {
        api := FakeWinApi()
        game := GameWithWindow()
        api.front := 1234, api.polite := true
        Assert(game.Focus())
        AssertEq(api.calls, ["ask"])
        AssertEq(api.target, 1234)
    }

    static Test_takes_the_front_from_no_other_program_once_the_pc_settles() {
        ; Nothing in front, another of the game's windows, SynSeeder's window (after Seed now).
        for front in [0, 4321, 7777, 7778] {
            api := FakeWinApi()
            game := GameWithWindow()
            Logs.capture := []
            api.front := front, api.polite := true
            api.idle := HllGame.SETTLE_SECONDS - 1  ; someone is still at it
            Assert(!game.Focus(), "took the front at once from " front)
            AssertEq(api.calls, ["flash"])
            AssertEq(LogsWith("The PC is in use; waiting until the mouse and keyboard have been idle for 10 s"), 1)
            Assert(game.WaitingForUser())
            api.idle := HllGame.SETTLE_SECONDS
            Assert(game.Focus(), "not in front from " front)
            AssertEq(api.calls, ["flash", "force+alt"])
            AssertEq(LogsWith("Brought the game to the front (" (front = 0 ? "no window" : front = 4321
                ? "another of its windows" : "SynSeeder's window") " was in front; mouse and keyboard idle for 10 s)"), 1)
            Patches.Undo()
        }
    }

    static Test_waits_while_someone_uses_the_pc() {
        api := FakeWinApi()
        game := GameWithWindow()
        Logs.capture := []
        api.idle := HllGame.IDLE_BEFORE_TAKEOVER - 1
        api.polite := true  ; Windows would let it (e.g. after its foreground lock timeout): it mustn't ask
        Assert(!game.Focus())
        Assert(!game.Focus())
        for call in api.calls
            Assert(call = "flash", "took the screen from someone using it: " call)
        AssertEq(Count(api.calls, "flash"), 1)
        AssertEq(LogsWith("in use"), 1)
        Assert(game.WaitingForUser())
        AssertEq(api.target, 1234)  ; so input meant for the game is dropped meanwhile
    }

    static Test_another_programs_window_is_never_asked_for() {
        ; Another program, one only named like SynSeeder, a window that's gone, and nothing in front of a locked PC.
        for front in [5678, 7779, 9999, 0] {
            api := FakeWinApi()
            game := GameWithWindow()
            api.front := front, api.polite := true, api.idle := 60, api.unlocked := false
            Assert(!game.Focus(), "took the front from " front)
            AssertEq(api.calls, ["flash"])
            Patches.Undo()
        }
    }

    static Test_waits_five_minutes_before_taking_over() {
        AssertEq(HllGame.IDLE_BEFORE_TAKEOVER, 300)
        api := FakeWinApi()
        game := GameWithWindow()
        Logs.capture := []
        api.idle := 299.4
        Assert(!game.Focus())
        AssertEq(api.calls, ["flash"])
        AssertEq(LogsWith("Another window is in front and the PC is in use; waiting until the mouse and keyboard have been idle for 5 min"), 1)
        api.idle := 300
        Assert(game.Focus())
        AssertEq(api.calls, ["flash", "force+alt"])
        AssertEq(LogsWith("Brought the game to the front (mouse and keyboard idle for 5 min)"), 1)
    }

    static Test_waits_for_the_pc_to_settle_when_the_game_comes_back_by_itself() {
        api := FakeWinApi()
        game := GameWithWindow()
        Logs.capture := []
        api.idle := 20
        Assert(!game.Focus())
        ; Someone clicked the game, or Windows switched to it when they minimised their window.
        api.front := 1234, api.polite := true, api.idle := 2
        Assert(!game.Focus(), "carried on under the hands of someone using the PC")
        AssertEq(LogsWith("not because of SynSeeder"), 1)
        Assert(InStr(Logs.capture[Logs.capture.Length], "last used 2s ago"), Logs.capture[Logs.capture.Length])
        Assert(game.WaitingForUser())  ; so it doesn't count against the time to get in
        api.idle := HllGame.SETTLE_SECONDS - 1
        Assert(!game.Focus())
        api.idle := HllGame.SETTLE_SECONDS
        Assert(game.Focus())
        AssertEq(LogsWith("not because of SynSeeder"), 1)  ; said once
        AssertEq(LogsWith("Brought the game to the front"), 0)
        Assert(!game.WaitingForUser())
        ; Already left alone when it came back: carries on at once, and says so.
        api.front := 5678, api.idle := 1
        Assert(!game.Focus())
        api.front := 1234, api.idle := 40
        Assert(game.Focus())
        AssertEq(LogsWith("not because of SynSeeder"), 2)
    }

    static Test_synseeders_own_takeover_is_logged_as_its_own() {
        api := FakeWinApi()
        game := GameWithWindow()
        Logs.capture := []
        api.idle := 20
        Assert(!game.Focus())  ; a wait
        ; The takeover gets the game in front, but it's still restoring from minimised.
        api.idle := HllGame.IDLE_BEFORE_TAKEOVER + 12, api.forced := false, api.restoring := true
        Assert(!game.Focus())
        api.front := 1234, api.restoring := false, api.polite := true
        Assert(game.Focus())
        AssertEq(LogsWith("Brought the game to the front (mouse and keyboard idle for 5 min 12 s)"), 1)
        AssertEq(LogsWith("not because of SynSeeder"), 0)
        ; And a plain takeover followed by the game in front says nothing more.
        api.front := 5678, api.idle := 1
        Assert(!game.Focus())
        api.idle := HllGame.IDLE_BEFORE_TAKEOVER, api.forced := true
        Assert(game.Focus())
        api.front := 1234
        Assert(game.Focus())
        AssertEq(LogsWith("not because of SynSeeder"), 0)
        AssertEq(LogsWith("Brought the game to the front"), 2)
    }

    static Test_a_game_restoring_from_minimised_is_not_someone_using_the_pc() {
        api := FakeWinApi()
        game := GameWithWindow()
        Logs.capture := []
        api.front := 1234  ; in front, but BringToFront is still restoring it
        Assert(!game.Focus())
        AssertEq(LogsWith("WARNING"), 0)
        Assert(!game.WaitingForUser())
        Assert(!Includes(api.calls, "flash"))
    }

    static Test_takes_the_front_once_the_pc_is_idle() {
        api := FakeWinApi()
        game := GameWithWindow()
        Logs.capture := []
        api.idle := 1
        Assert(!game.Focus())
        api.idle := HllGame.IDLE_BEFORE_TAKEOVER
        Assert(game.Focus())
        AssertEq(api.calls[api.calls.Length], "force+alt")
        AssertEq(LogsWith("Brought the game to the front"), 1)
        Assert(!game.WaitingForUser())
        ; Someone grabs another window again: a new wait, flagged again.
        api.idle := 0
        Assert(!game.Focus())
        AssertEq(Count(api.calls, "flash"), 2)
    }

    static Test_refused_takeover_taps_alt_only_once_and_logs_once() {
        api := FakeWinApi()
        game := GameWithWindow()
        Logs.capture := []
        api.idle := HllGame.IDLE_BEFORE_TAKEOVER + 45, api.forced := false
        api.frontPid := DllCall("GetCurrentProcessId", "UInt")
        loop 4
            Assert(!game.Focus())
        forces := []
        for call in api.calls
            if InStr(call, "force")
                forces.Push(call)
        AssertEq(forces, ["force+alt", "force", "force", "force"])
        refused := []
        for line in Logs.capture
            if InStr(line, "Couldn't bring the game to the front")
                refused.Push(line)
        AssertEq(refused.Length, 1)
        Assert(InStr(refused[1], "(" ProcessGetName(api.frontPid) " has it)"), refused[1])  ; says which program is in the way
        Assert(!Includes(api.calls, "flash"))
        Assert(!game.WaitingForUser())  ; refused isn't the player's doing; timeouts still apply
        ; Once it gets to the front, the next wait may tap Alt again.
        api.forced := true
        Assert(game.Focus())
        api.forced := false
        game.Focus()
        AssertEq(api.calls[api.calls.Length], "force+alt")
    }

    static Test_a_game_still_restoring_is_not_a_refusal() {
        api := FakeWinApi()
        game := GameWithWindow()
        Logs.capture := []
        api.idle := HllGame.IDLE_BEFORE_TAKEOVER + 45, api.forced := false, api.restoring := true
        Assert(!game.Focus())
        AssertEq(LogsWith("WARNING"), 0)  ; nothing is in the way; it's ready on the next try
        api.restoring := false
        game.Focus()
        AssertEq(api.calls[api.calls.Length], "force+alt")  ; the Alt tap wasn't used up
    }

    static Test_no_window_no_focus() {
        api := FakeWinApi()
        game := HllGame(SeederConfig(), FakeClock())
        game.DefineProp("Window", {Call: (*) => 0})
        Assert(!game.Focus())
        AssertEq(api.calls, [])
    }

    ; The screen

    static Test_a_failed_capture_keeps_the_last_frame_and_is_logged_once() {
        screen := GameScreen(Map())
        Assert(screen.Refresh(), "Windows' screen couldn't be read at all")
        Logs.capture := []
        Patches.Set(GameScreen, "_Copy", (*) => false)
        Assert(!screen.Refresh())
        Assert(!screen.Refresh())
        Assert(screen.vision.ready)  ; still matching against the last frame
        AssertEq(Logs.capture.Length, 1)
        Assert(InStr(Logs.capture[1], "WARNING Couldn't capture the screen") = 1, Logs.capture[1])
        Patches.Undo()
        Assert(screen.Refresh())
        Patches.Set(GameScreen, "_Copy", (*) => false)
        Assert(!screen.Refresh())
        AssertEq(Logs.capture.Length, 2)  ; a new run of failures is logged again
    }

    ; The screen asks the button finder for the JOIN on the row it's given, not
    ; for the best JOIN anywhere, which can be another server's.
    static Test_the_screen_looks_for_join_only_on_the_rows_height() {
        screen := GameScreen(Map())
        finder := screen.vision
        finder.ready := true
        asked := []
        finder.DefineProp("JoinOnRow", {Call: (this, row) => (asked.Push(row), row[2] = 606 ? [1290, 610] : "")})
        finder.DefineProp("Find", {Call: (this, name, region := "") => name = "browser_join" ? [1290, 300] : ""})
        AssertEq(screen.JoinOnRow([700, 606]), [1290, 610])
        AssertEq(screen.JoinOnRow([700, 527]), "")
        AssertEq(asked, [[700, 606], [700, 527]])
    }

    ; A 1280x720 capture, black but for a noisy gray patch around create_unit's
    ; spot with a 64x20 button image in it; and that image. More ``noise``
    ; (+- levels per pixel) makes the image match less well.
    static ButtonFrame(noise) {
        img := VisionGray(64, 20)
        loop 20 {
            y := A_Index - 1
            loop 64 {
                x := A_Index - 1
                NumPut("UChar", 60 + 120 * ((x // 8 + y // 5) & 1) + x, img.buf, y * 64 + x)
            }
        }
        w := 1280, h := 720, frame := Buffer(w * h * 4, 0)
        cx := Round(0.2917 * w), cy := Round(0.3056 * h), left := cx - 32, top := cy - 10
        seed := 12345
        loop 80 {
            y := cy - 40 + A_Index - 1
            loop 160 {
                x := cx - 80 + A_Index - 1
                v := 30
                if x >= left && x < left + 64 && y >= top && y < top + 20
                    v := NumGet(img.buf, (y - top) * 64 + x - left, "UChar")
                seed := Mod(seed * 1103515245 + 12345, 0x80000000)
                v := Max(0, Min(255, v + Round(((seed >> 16) & 0x7FFF) / 0x7FFF * 2 * noise - noise)))
                NumPut("UInt", v | v << 8 | v << 16, frame, (y * w + x) * 4)
            }
        }
        finder := Vision(Map("create_unit", [{img: img, cut: 720, tag: ""}]))
        finder.SetFrame(frame.Ptr, w, h, w * 4, w, h, 1)
        return {finder: finder, frame: frame, x: cx, y: cy}
    }

    ; A button in Vision.THRESHOLDS counts as found at its own, lower score:
    ; here a create_unit that scores between its 0.80 and the usual 0.85.
    static Test_buttons_with_their_own_threshold_are_found_below_the_usual_one() {
        t := GameTests.ButtonFrame(139)
        score := t.finder.BestScore("create_unit")
        Assert(score >= 0.80 && score < Vision.THRESHOLD, "the test image scores " score)
        AssertEq(t.finder.Find("create_unit"), [t.x, t.y])
        Patches.Value(Vision, "THRESHOLDS", Map())
        AssertEq(t.finder.Find("create_unit"), "")
    }

    static Test_flow_skips_a_tick_without_a_screen() {
        screen := FakeScreen(HappyPath())
        screen.Show("menu_enlist")
        screen.DefineProp("Refresh", {Call: (*) => false})
        AssertEq(Flow.CurrentScreen(screen), Flow.NO_SCREEN)
    }

    ; Stopping while the launcher starts the game

    static Test_no_launch_when_already_asked_to_stop() {
        starts := []
        Patches.Set(HllGame, "Start", (this, uri) => starts.Push(uri))
        game := HllGame(SeederConfig(), StoppingClock(0), FakeClock())
        AssertThrows(SeedStopped, () => game.Launch(60))
        AssertEq(starts, [])
    }

    static Test_a_stop_during_launch_closes_the_game_when_it_starts_late() {
        Patches.Set(HllGame, "Start", (*) => "")
        ended := []
        Patches.Set(HllGame, "_End", (this, pid) => ended.Push(pid))
        late := FakeClock()
        game := HllGame(SeederConfig(), StoppingClock(10), late)
        game.DefineProp("Window", {Call: (*) => 0})
        game.DefineProp("Pid", {Call: (*) => late.at >= 30 ? 4321 : 0})  ; shows up 30 s after the stop
        AssertThrows(SeedStopped, () => game.Launch(300))
        AssertEq(ended, [4321])
        Assert(late.at < HllGame.LATE_START_SECONDS)
    }

    static Test_a_stop_during_launch_watches_for_a_late_start_for_a_while() {
        Patches.Set(HllGame, "Start", (*) => "")
        Patches.Set(HllGame, "_End", (*) => Fail("nothing to close"))
        late := FakeClock()
        game := HllGame(SeederConfig(), StoppingClock(10), late)
        game.DefineProp("Window", {Call: (*) => 0})
        game.DefineProp("Pid", {Call: (*) => 0})
        AssertThrows(SeedStopped, () => game.Launch(300))
        AssertEq(late.at, HllGame.LATE_START_SECONDS)
    }

    static Test_a_stop_late_in_the_launch_still_watches_the_whole_time() {
        Patches.Set(HllGame, "Start", (*) => "")
        ended := []
        Patches.Set(HllGame, "_End", (this, pid) => ended.Push(pid))
        late := FakeClock()
        game := HllGame(SeederConfig(), StoppingClock(290), late)  ; 10 s before the launch would give up
        game.DefineProp("Window", {Call: (*) => 0})
        game.DefineProp("Pid", {Call: (*) => late.at >= 40 ? 4321 : 0})  ; shows up 40 s after the stop
        AssertThrows(SeedStopped, () => game.Launch(300))
        AssertEq(ended, [4321])
    }

    ; The key the game's keyboard layout types a letter with is pressed; on a
    ; Russian or Greek layout no key types f, so F's own key is.
    static Test_letters_reach_the_game_on_a_layout_that_cant_type_them() {
        asked := []
        scancode(answer) {
            Patches.Set(WinApi, "VkScan", (this, key, layout) => (asked.Push(key), answer))
            return WinApi._Scancode("f")
        }
        us := scancode(0x46)     ; the F key types f, as on a US layout
        other := scancode(0x47)  ; the G key does
        none := scancode(-1)     ; no key does
        AssertEq(asked, ["f", "f", "f"], "_Scancode didn't ask the game's layout")
        Assert(us && other && other != us, "the F and G keys' scancodes: " us ", " other)
        AssertEq(none, us)
    }

    static Test_idle_counts_from_the_last_input() {
        AssertEq(WinApi.IdleMs(50000, 20000, "", ""), 30000)
        ; The latest input was ours: count from the player's, or from ours if we never saw theirs.
        AssertEq(WinApi.IdleMs(50000, 20016, 20000, 5000), 45000)
        AssertEq(WinApi.IdleMs(50000, 20016, 20000, ""), 30000)
        ; The player moved the mouse after our click.
        AssertEq(WinApi.IdleMs(50000, 45000, 20000, 5000), 5000)
    }

    static Test_letters_are_pressed_on_any_keyboard_layout() {
        AssertEq(WinApi.KeyFor("f", 0x46), 0x46)      ; US: F types f
        AssertEq(WinApi.KeyFor("a", 0x51), 0x51)      ; French: the key marked A is VK_Q
        AssertEq(WinApi.KeyFor("f", -1), 0x46)        ; Russian: no key types f, so F's own key
        AssertEq(WinApi.KeyFor("y", 0x159), 0x59)     ; only with Shift: Y's own key, without it
        AssertEq(WinApi.KeyFor("d", 0x644), 0x44)     ; only with AltGr
        AssertEq(WinApi.KeyFor("1", -1), 0xFF)        ; not a letter: unchanged
    }

    static Test_idle_survives_tick_wraparound() {
        AssertEq(WinApi.IdleMs(1000, 2 ** 32 - 4000, "", ""), 5000)
        AssertEq(WinApi.IdleMs(1000, 2 ** 32 - 4000, 2 ** 32 - 4100, 2 ** 32 - 9000), 10000)
    }

    static Test_input_stamped_a_little_ahead_is_input_now() {
        ; Another program's SendInput can give its own time stamp.
        AssertEq(WinApi.IdleMs(1000, 1500, "", ""), 0)
        AssertEq(WinApi.IdleMs(2 ** 32 - 100, 50, "", ""), 0)  ; ahead, across the wrap
    }

    static Test_a_switch_during_a_key_press_counts_as_the_players_input() {
        last := {tick: 20100}  ; the player's Alt+Tab, 100 ms after our key down: inside the slack
        game := {inFront: true}
        Patches.Set(WinApi, "_LastInput", (*) => last.tick)
        Patches.Set(WinApi, "_OnTarget", (*) => game.inFront)
        Patches.Value(WinApi, "playerInputTick", 5000)
        Patches.Value(WinApi, "ownInputTick", 20000)
        WinApi._Send([], "release")  ; the key-up with the game still in front: taken as ours
        AssertEq(WinApi.playerInputTick, 5000)
        game.inFront := false
        Patches.Value(WinApi, "ownInputTick", 20000)
        WinApi._Send([], true)  ; a nudge to bring the game back: not in front, as expected
        AssertEq(WinApi.playerInputTick, 5000)
        Patches.Value(WinApi, "ownInputTick", 20000)
        WinApi._Send([], "release")  ; the key-up goes out with the game no longer in front: theirs
        AssertEq(WinApi.playerInputTick, 20100)
    }

    static Test_log_spans() {
        AssertEq(HllGame.Span(10), "10 s")
        AssertEq(HllGame.Span(59.6), "1 min")
        AssertEq(HllGame.Span(300), "5 min")
        AssertEq(HllGame.Span(312.2), "5 min 12 s")
    }

    ; The Epic launcher's install list

    static Test_finds_vietnam_in_epics_own_folder() {
        ; Epic names the folder Hell_Let_Loose_Vietnam
        AssertEq(HllGame.DetectEpicAppName(Installed(Plus(Fortnite(), Vietnam()))), HLLV)
    }

    static Test_finds_vietnam_by_its_app_name_in_any_folder() {
        for folder in ["D:\Games\HLLV", "E:\Epic\Something Else"]
            AssertEq(HllGame.DetectEpicAppName(Installed(Plus(Fortnite(), Vietnam(folder)))), HLLV)
    }

    static Test_falls_back_to_the_folder_name_if_the_app_name_changes() {
        for folder in ["X:\Epic Games\Hell_Let_Loose_Vietnam", "C:\Epic Games\HellLetLooseVietnam", "D:\Hell Let Loose - Vietnam"] {
            entry := Vietnam(folder, "0123456789abcdef0123456789abcdef")
            AssertEq(HllGame.DetectEpicAppName(Installed(Plus(Fortnite(), entry))),
                StrReplace(HLLV, HllGame.EPIC_APP_NAME, entry["AppName"]), folder)
        }
    }

    static Test_the_app_name_beats_another_entry_in_a_matching_folder() {
        extra := Vietnam(, "ffffffffffffffffffffffffffffffff")  ; e.g. extra content installed alongside
        AssertEq(HllGame.DetectEpicAppName(Installed([extra, Vietnam()])), HLLV)
    }

    static Test_original_hell_let_loose_is_not_vietnam() {
        entry := Fortnite()[2]
        entry["InstallLocation"] := "X:\Epic Games\HellLetLoose", entry["AppName"] := "Lacebark"
        AssertEq(HllGame.DetectEpicAppName(Installed([entry])), "")
    }

    static Test_only_the_app_name_when_the_ids_are_missing() {
        entry := Map("InstallLocation", "X:\Epic Games\Hell_Let_Loose_Vietnam", "AppName", "d7361b7d6fa94097bcadeac4b1f785fb")
        AssertEq(HllGame.DetectEpicAppName(Installed([entry])), "d7361b7d6fa94097bcadeac4b1f785fb")
    }

    static Test_unreadable_install_list() {
        path := App.Dir "\LauncherInstalled.dat"
        for text in ["", "not json", "[]", '{"InstallationList": null}', '{"InstallationList": [1, null]}'] {
            try FileDelete(path)
            FileAppend(text, path, "UTF-8-RAW")
            AssertEq(HllGame.DetectEpicAppName(path), "", text)
        }
    }

    static Test_not_installed() {
        AssertEq(HllGame.DetectEpicAppName(Installed(Fortnite())), "")
        AssertEq(HllGame.DetectEpicAppName(App.Dir "\missing.dat"), "")
    }

    static Test_epic_launch_link_matches_epics_shortcuts() {
        path := Installed(Plus(Fortnite(), Vietnam()))
        real := HllGame.GetOwnPropDesc("DetectEpicAppName").Call
        Patches.Set(HllGame, "DetectEpicAppName", (this, manifest := "") => real(this, path))
        config := SeederConfig()
        config.launcher := "epic"
        AssertEq(HllGame(config, FakeClock()).LaunchUri(),
            "com.epicgames.launcher://apps/3b51901c38644473a9cba942253b3a41%3Acc1ab2f4d934407c8f1e6463d9c1dbdf"
            . "%3Ad7361b7d6fa94097bcadeac4b1f785fb?action=launch&silent=true")
    }

    static Test_epic_app_name_from_settings_wins() {
        lookedUp(*) {
            throw Error("shouldn't look")
        }
        Patches.Set(HllGame, "DetectEpicAppName", lookedUp)
        encoded := StrReplace(HLLV, ":", "%3A")
        ; copied from a shortcut: not encoded twice
        for item in [["SomeApp", "SomeApp"], [HLLV, encoded], [" " encoded " ", encoded]] {
            config := SeederConfig()
            config.launcher := "epic", config.epic_app_name := item[1]
            AssertEq(HllGame(config, FakeClock()).LaunchUri(), "com.epicgames.launcher://apps/" item[2] "?action=launch&silent=true")
        }
    }

    static Test_epic_without_the_game_installed() {
        Patches.Set(HllGame, "DetectEpicAppName", (*) => "")
        config := SeederConfig()
        config.launcher := "epic"
        try {
            HllGame(config, FakeClock()).LaunchUri()
            message := ""
        } catch as err {
            message := err.Message
        }
        AssertEq(message, "Couldn't find HLL Vietnam in the Epic launcher")
    }

    static Test_steam_launch_link() {
        AssertEq(HllGame(SeederConfig(), FakeClock()).LaunchUri(), "steam://rungameid/3079210")
    }

    static Test_finds_the_game_from_either_store() {
        ; Every saved config.json has Steam's name, and Epic's build runs under another one
        for wanted in ["HLLVietnam-Win64-Shipping.exe", "HLLVietnamEpicGamesStore-Win64-Shipping.exe", ""] {
            config := SeederConfig()
            config.process_name := wanted
            for running in ["HLLVietnam-Win64-Shipping.exe", "HLLVietnamEpicGamesStore-Win64-Shipping.exe"]
                Assert(HllGame(config, FakeClock()).Matches(running), wanted " should find " running)
        }
    }

    static Test_launchers_and_other_games_are_not_the_game() {
        ; Epic's launcher stub, EAC, the original HLL
        game := HllGame(SeederConfig(), FakeClock())
        for running in ["Launch_HLL.exe", "HLLVietnamEpicGamesStore.exe", "start_protected_game.exe", "HLL-Win64-Shipping.exe"]
            Assert(!game.Matches(running), running)
    }

    static Test_a_blank_process_name_means_any_hll_build() {
        config := SeederConfig()
        config.process_name := ""
        Assert(HllGame(config, FakeClock()).Matches("HLLVietnamEpicGamesStore-Win64-Shipping.exe"))
        Assert(HllGame(config, FakeClock()).Matches("HLL-Win64-Shipping.exe"))
    }

    static Test_a_custom_process_name_is_matched_exactly() {
        config := SeederConfig()
        config.process_name := "Other-Win64-Shipping.exe"
        game := HllGame(config, FakeClock())
        Assert(game.Matches("other-win64-shipping.exe"))
        Assert(!game.Matches("HLLVietnamEpicGamesStore-Win64-Shipping.exe"))
    }

    static Test_no_game_running_here() {
        game := HllGame(SeederConfig(), FakeClock())
        Assert(!game.Running())
        AssertEq(game.Rect(), "")
    }
}
