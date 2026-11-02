; Finding, starting and focusing the game (ported from the first SynSeeder's
; tests/test_game.py and tests/test_launch.py).

; Swaps WinApi's window calls for ones that record what they were asked.
FakeWinApi() {
    api := {polite: false, forced: true, idle: 0.0, calls: [], target: "", frontPid: 0, restoring: false}
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
        api.polite := true
        Assert(game.Focus())
        AssertEq(api.calls, ["ask"])
        AssertEq(api.target, 1234)
    }

    static Test_waits_while_someone_uses_the_pc() {
        api := FakeWinApi()
        game := GameWithWindow()
        Logs.capture := []
        api.idle := HllGame.IDLE_BEFORE_TAKEOVER - 1
        Assert(!game.Focus())
        Assert(!game.Focus())
        for call in api.calls
            Assert(!InStr(call, "force"), "took the screen from someone using it")
        AssertEq(Count(api.calls, "flash"), 1)
        AssertEq(LogsWith("in use"), 1)
        Assert(game.WaitingForUser())
        AssertEq(api.target, 1234)  ; so input meant for the game is dropped meanwhile
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
        api.idle := 60, api.forced := false
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
        api.idle := 60, api.forced := false, api.restoring := true
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

    static Test_idle_counts_from_the_last_input() {
        AssertEq(WinApi.IdleMs(50000, 20000, "", ""), 30000)
        ; The latest input was ours: count from the player's, or from ours if we never saw theirs.
        AssertEq(WinApi.IdleMs(50000, 20016, 20000, 5000), 45000)
        AssertEq(WinApi.IdleMs(50000, 20016, 20000, ""), 30000)
        ; The player moved the mouse after our click.
        AssertEq(WinApi.IdleMs(50000, 45000, 20000, 5000), 5000)
    }

    static Test_idle_survives_tick_wraparound() {
        AssertEq(WinApi.IdleMs(1000, 2 ** 32 - 4000, "", ""), 5000)
        AssertEq(WinApi.IdleMs(1000, 2 ** 32 - 4000, 2 ** 32 - 4100, 2 ** 32 - 9000), 10000)
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
