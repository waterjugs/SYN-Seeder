; Settings, server stats, the daily task's XML, the command line and helpers
; (partly ported from the first SynSeeder's tests).

; The live Syndicate stats page, trimmed (2026-10-24).
LIVE_STATS := '{"result": {"name": {"name": "Syndicate | Competitive Server | Discord.gg/syn-hll | Radical Gaming Network", "short_name": "Syn Nam"}, "player_count": 11, "max_player_count": 100, "player_count_by_team": {"allied": 6, "axis": 5}, "time_remaining": 2327.0, "match_time": 5400}, "failed": false}'

TaskField(xml, tag) => RegExMatch(xml, "<" tag ">([^<]*)</" tag ">", &m) ? m[1] : ""

ThrowOffline(*) {
    throw Error("offline")
}

class MiscTests {
    ; Settings

    static Test_settings_round_trip() {
        path := App.Dir "\config.json"
        config := SeederConfig()
        config.start_time := "06:35", config.launcher := "epic"
        config.Save(path)
        loaded := SeederConfig.Load(path)
        AssertEq(loaded.start_time, "06:35")
        AssertEq(loaded.launcher, "epic")
        Assert(loaded.auto_update)
    }

    static Test_settings_saved_with_a_bom_and_unknown_keys() {
        path := App.Dir "\config.json"
        FileAppend('{"start_time": "08:00", "old_setting": 1}', path, "UTF-8")  ; with a byte-order mark
        AssertEq(SeederConfig.Load(path).start_time, "08:00")
    }

    static Test_missing_settings_give_defaults() {
        config := SeederConfig.Load(App.Dir "\nope.json")
        for field in SeederConfig.FIELDS
            AssertEq(config.%field[1]%, field[2], field[1])
    }

    static Test_older_settings_files_get_the_leave_delay() {
        path := App.Dir "\config.json"
        FileAppend('{"start_time": "08:00", "seeded_threshold": 80}', path, "UTF-8-RAW")
        AssertEq(SeederConfig.Load(path).leave_delay_minutes, 10)
    }

    static Test_settings_file_matches_the_first_seeders() {
        path := App.Dir "\config.json"
        SeederConfig().Save(path)
        text := FileRead(path, "UTF-8")
        Assert(SubStr(text, 1, 25) == '{`n  "server_name": "Syndi', SubStr(text, 1, 40))
        Assert(InStr(text, '"auto_update": true,') && InStr(text, '"max_minutes": 240`n}'), text)
        Assert(InStr(text, '"crcon_url": "https://syn-stats-nam.radicalgamingstats.com/api/get_public_info"'), text)
    }

    ; The file can be edited by hand. A value that can't be used keeps its
    ; default and is named, rather than breaking a run halfway (text for a
    ; number), ending every run at once (no player count to reach) or having
    ; a run ask the stats page without a pause (0 seconds between looks).
    static Test_settings_that_cant_be_used_keep_their_defaults() {
        path := App.Dir "\config.json"
        FileAppend('{"start_time": "06:35", "launcher": "epic", "leave_delay_minutes": 2.5, "crcon_url": "ftp://example.com/x", '
            . '"seeded_threshold": null, "steam_app_id": "3079210", "process_name": {"exe": "x"}, "auto_update": "false", '
            . '"pinged_from": "25:00", "poll_seconds": 0, "max_restarts": 2.5, "max_minutes": "abc"}', path, "UTF-8-RAW")
        config := SeederConfig.Load(path)
        AssertEq([config.start_time, config.launcher, config.leave_delay_minutes], ["06:35", "epic", 2.5])
        bad := ["crcon_url", "seeded_threshold", "steam_app_id", "process_name", "auto_update", "pinged_from",
            "poll_seconds", "max_restarts", "max_minutes"]
        AssertEq(config.ignored, bad)
        usual := SeederConfig()
        for name in bad
            AssertEq(config.%name%, usual.%name%, name)
        AssertEq(usual.ignored, [])
    }

    static Test_every_default_setting_passes_its_own_check() {
        for field in SeederConfig.FIELDS
            Assert(SeederConfig.Valid(field[1], field[2]), field[1])
        Assert(!SeederConfig.Valid("no_such_setting", 1))
    }

    ; Left blank (or null) by hand, process_name means any HLL build: that stays.
    static Test_a_blank_process_name_is_still_a_setting() {
        path := App.Dir "\config.json"
        FileAppend('{"process_name": null, "epic_app_name": ""}', path, "UTF-8-RAW")
        config := SeederConfig.Load(path)
        AssertEq([config.process_name, config.epic_app_name, config.ignored], ["", "", []])
    }

    ; What a saved file holds always loads back whole.
    static Test_saved_settings_all_pass_the_check() {
        path := App.Dir "\config.json"
        config := SeederConfig()
        config.seed_when_pinged := true, config.auto_update := false, config.pinged_from := "8:30"
        config.Save(path)
        loaded := SeederConfig.Load(path)
        AssertEq(loaded.ignored, [])
        AssertEq([loaded.seed_when_pinged, loaded.auto_update, loaded.pinged_from], [1, 0, "8:30"])
    }

    static Test_broken_settings_file_is_an_error() {
        path := App.Dir "\config.json"
        FileAppend("{not json", path, "UTF-8-RAW")
        try {
            SeederConfig.Load(path)
            threw := false
        } catch {
            threw := true
        }
        Assert(threw)
    }

    ; Server stats

    static Test_parse_live_shape() {
        status := ServerStats.Parse(Json.Load(LIVE_STATS))
        AssertEq(status.players, 11)
        AssertEq([status.allied, status.axis], [6, 5])
        AssertEq(status.timeRemaining, 2327.0)
        Assert(InStr(status.name, "Syndicate | Competitive Server") = 1)
    }

    static Test_weaker_side() {
        AssertEq(ServerStats.WeakerSide(ServerStats.Parse(Json.Load(LIVE_STATS))), "axis")
        AssertEq(ServerStats.WeakerSide(FakeStatus(10, 5, 5)), "allies")
    }

    static Test_fetch_is_empty_when_unreachable() {
        AssertEq(ServerStats.Fetch("http://127.0.0.1:9/nothing", 1), "")
    }

    ; The stats page is someone else's. It gets one time limit in all, however
    ; slowly it answers, and an answer far bigger than a real one is refused.
    static Test_fetch_gives_the_stats_page_one_time_limit_and_a_size_limit() {
        answer := FakeResponse(LIVE_STATS)
        asked := []
        start(this, url, accept, timeout, async) {
            asked.Push([url, accept, timeout, async])
            return answer
        }
        Patches.Set(Http, "Start", start)
        AssertEq(ServerStats.Fetch("https://stats.example/api", 2).players, 11)
        AssertEq(asked, [["https://stats.example/api", "application/json", 2, true]])
        Logs.capture := []
        answer := FakeResponse(LIVE_STATS, false)  ; never answers
        t0 := A_TickCount
        AssertEq(ServerStats.Fetch("https://stats.example/api", 0.3), "")
        took := A_TickCount - t0
        Assert(answer.aborted, "the request wasn't stopped")
        Assert(took >= 300 && took < 3000, "took " took " ms")
        Assert(InStr(Logs.capture[1], "no answer in 0.3 seconds"), Logs.capture[1])
        pad := "x"
        while StrLen(pad) <= ServerStats.MAX_BYTES
            pad .= pad
        answer := FakeResponse('{"result": {"player_count": 11, "pad": "' pad '"}}')
        AssertEq(ServerStats.Fetch("https://stats.example/api", 2), "")
        Assert(InStr(Logs.capture[2], "the answer is too big"), SubStr(Logs.capture[2], 1, 200))
    }

    ; A seed-call check asks without following a redirect; everything else follows them.
    static Test_requests_follow_redirects_unless_told_not_to() {
        real := Http.Start
        sent := []
        start(this, url, accept := "application/json", timeout := 15, async := false, redirects := true) {
            sent.Push([url, async, redirects])
            return FakeResponse("{}")
        }
        Patches.Set(Http, "Start", start)
        SeedCalls._Send("https://calls.example/seed-call")
        AssertEq(Http.Text("https://files.example/x"), "{}")
        AssertEq(sent, [["https://calls.example/seed-call", true, false], ["https://files.example/x", false, true]])
        Assert(real.MaxParams >= 6, "Http.Start takes no redirects setting")
    }

    ; WinHTTP hands back a new array for every read of ResponseBody, freed as
    ; soon as nothing holds it; the text must be copied while it's held.
    static Test_response_text_survives_the_array_being_freed() {
        for n in [1200, 5000, 70000] {
            want := '{"pad":"' StrReplace(Format("{:" n "}", ""), " ", "é") '","n":1}'
            AssertEq(Http.BodyText(FakeResponse(want)), want, n " characters")
        }
        AssertEq(Http.BodyText(FakeResponse("")), "")
    }

    static Test_failed_response_is_an_error() {
        for text in ['{"result": null, "failed": true, "error": "rcon down"}', '{"result": "oops", "failed": false}'] {
            try {
                ServerStats.Parse(Json.Load(text))
                threw := false
            } catch ValueError {
                threw := true
            }
            Assert(threw, text)
        }
    }

    ; The daily task

    static Test_task_starts_today_if_time_is_still_ahead() {
        xml := DailyTask.Xml("19:30", "C:\x\SynSeeder.exe", "--seed", "20261024080000")
        AssertEq(TaskField(xml, "StartBoundary"), "2026-10-24T19:30:00")
        AssertEq(TaskField(xml, "DaysInterval"), "1")
    }

    static Test_task_starts_tomorrow_if_time_has_passed() {
        AssertEq(TaskField(DailyTask.Xml("07:00", "p", "--seed", "20261024080000"), "StartBoundary"), "2026-10-25T07:00:00")
        AssertEq(TaskField(DailyTask.Xml("08:00", "p", "--seed", "20261231080000"), "StartBoundary"), "2027-01-01T08:00:00")
    }

    static Test_task_runs_on_battery_late_and_once() {
        xml := DailyTask.Xml("07:00", "p", "--seed")
        AssertEq(TaskField(xml, "DisallowStartIfOnBatteries"), "false")
        AssertEq(TaskField(xml, "StartWhenAvailable"), "true")
        AssertEq(TaskField(xml, "MultipleInstancesPolicy"), "IgnoreNew")
        AssertEq(TaskField(xml, "LogonType"), "InteractiveToken")
        AssertEq(TaskField(xml, "RunLevel"), "LeastPrivilege")
        Assert(SubStr(xml, 1, 39) == '<?xml version="1.0" encoding="UTF-16"?>', SubStr(xml, 1, 60))
    }

    static Test_task_command_is_escaped() {
        xml := DailyTask.Xml("07:00", "C:\Users\A&B\SynSeeder.exe", "--seed")
        AssertEq(TaskField(xml, "Command"), "C:\Users\A&amp;B\SynSeeder.exe")
        AssertEq(TaskField(xml, "Arguments"), "--seed")
    }

    static Test_script_seed_command_runs_the_script() {
        command := DailyTask.SeedCommand()
        AssertEq(command[1], A_AhkPath)
        AssertEq(command[2], QuoteArg(A_ScriptFullPath) " --seed")
    }

    ; The command line

    static Test_command_line() {
        opts := ParseArgs([])
        Assert(!opts.seed && !opts.record && !opts.selftest)
        opts := ParseArgs(["--seed", "--max-minutes", "5"])
        Assert(opts.seed)
        AssertEq(opts.maxMinutes, 5)
        AssertEq(opts.passOn, "--seed --max-minutes 5")
        opts := ParseArgs(["--install-to", "C:\Program Files\SynSeeder.exe", "--old-pid", "11", "--old-pid=10", "--seed"])
        AssertEq(opts.installTo, "C:\Program Files\SynSeeder.exe")
        AssertEq(opts.oldPids, [11, 10])
        AssertEq(opts.passOn, "--seed")
        opts := ParseArgs(["--record", "--minutes=2", "--every", "1.5"])
        Assert(opts.record)
        AssertEq([opts.minutes, opts.every], [2, 1.5])
        opts := ParseArgs(["--selftest", "out.log", "--what"])
        Assert(opts.selftest)
        AssertEq(opts.selftestLog, "out.log")
        AssertEq(opts.unknown, ["--what"])
    }

    static Test_command_line_needs_values() {
        for args in [["--max-minutes"], ["--minutes", "lots"]] {
            try {
                ParseArgs(args)
                threw := false
            } catch ValueError {
                threw := true
            }
            Assert(threw, JoinList(args, " "))
        }
    }

    ; Helpers

    static Test_quote_arg() {
        AssertEq(QuoteArg("plain"), "plain")
        AssertEq(QuoteArg(""), '""')
        AssertEq(QuoteArg("C:\Program Files\SynSeeder.exe"), '"C:\Program Files\SynSeeder.exe"')
        AssertEq(QuoteArg('say "hi"'), '"say \"hi\""')
        AssertEq(QuoteArg("C:\dir with space\"), '"C:\dir with space\\"')
    }

    static Test_command_line_paths_start_where_the_program_was_started() {
        AssertEq(StartPath("C:\logs\selftest.log"), "C:\logs\selftest.log")
        AssertEq(StartPath("\\server\share\a.png"), "\\server\share\a.png")
        AssertEq(StartPath("build\fixtures"), A_InitialWorkingDir "\build\fixtures")
        AssertEq(StartPath(""), "")
    }

    static Test_uri_quote_and_unquote() {
        AssertEq(UriQuote("a:b c/é~_.-"), "a%3Ab%20c%2F%C3%A9~_.-")
        AssertEq(UriUnquote("a%3Ab%20c%2F%C3%A9"), "a:b c/é")
        AssertEq(UriUnquote("100%"), "100%")
        AssertEq(UriUnquote("%zz%3a"), "%zz:")
    }

    static Test_json_round_trip() {
        text := '{"a": [1, 2.5, -3e2, true, false, null], "b": "quote \" slash \\ newline \n tab \t \u00e9 \ud83c", "c": {}}'
        data := Json.Load(text)
        AssertEq(data["a"], [1, 2.5, -300.0, 1, 0, ""])
        AssertEq(data["b"], 'quote " slash \ newline `n tab `t é ' Chr(0xD83C))
        AssertEq(Json.Load(Json.Dump(data))["b"], data["b"])
        AssertEq(Json.Dump(Map("x", Json.Bool(true), "n", 0.1, "s", "é")), '{"n":0.1,"s":"é","x":true}')
        AssertEq(Json.Dump(Map("b", 1, "a", 2), "", ["b", "a"]), '{"b":1,"a":2}')
        AssertEq(Json.Dump([]), "[]")
    }

    ; Release notes can be long; a regular expression over the whole string
    ; ran out of PCRE recursion at about 3,000 characters.
    static Test_json_reads_long_strings() {
        line := 'Fixed the \"Join\" button \u00e9\\ and more.\n'
        body := ""
        loop 800
            body .= line
        data := Json.Load('{"tag_name": "v1.2.0", "body": "' body '", "after": "x\\"}')
        AssertEq(StrLen(data["body"]), 800 * 37)
        AssertEq(SubStr(data["body"], 1, 37), 'Fixed the "Join" button é\ and more.`n')
        AssertEq(data["after"], "x\")
        plain := ""
        loop 20000
            plain .= "a"
        AssertEq(StrLen(Json.Load('["' plain '"]')[1]), 20000)
    }

    static Test_json_rejects_broken_text() {
        for text in ["", "{", "[1,]", '{"a" 1}', "tru", '"open', "1 2", '"a\\"b"', '"bad \x"', '"\u12"', '"tab' "`t" '"', '"end\"'] {
            try {
                Json.Load(text)
                threw := false
            } catch {
                threw := true
            }
            Assert(threw, text)
        }
    }

    static Test_minutes_text() {
        AssertEq(MinutesText(245), "4 min 5 s")
        AssertEq(MinutesText(59.6), "1 min 0 s")
    }

    static Test_version_numbers() {
        AssertEq(App.ParseVersion("v1.2.3"), [1, 2, 3])
        AssertEq(App.ParseVersion("1.10.0"), [1, 10, 0])
        AssertEq(App.ParseVersion("v1.2"), "")
        AssertEq(App.ParseVersion("v1.2.3-beta"), "")
        AssertEq(App.CompareVersions([1, 10, 0], [1, 9, 9]), 1)
        AssertEq(App.CompareVersions([1, 1, 0], [1, 1, 0]), 0)
        AssertEq(App.CompareVersions([0, 9, 0], [1, 0, 0]), -1)
        Assert(App.ParseVersion(App.VERSION) != "")
    }

    static Test_version_matches_the_exe_details() {
        text := FileRead(A_ScriptDir "\..\SynSeeder.ahk", "UTF-8")
        Assert(RegExMatch(text, "m)^;@Ahk2Exe-SetVersion (\S+)$", &m), "no SetVersion line")
        AssertEq(m[1], App.VERSION)
    }

    ; Button images

    static Test_button_checksums_match_the_templates() {
        folder := A_ScriptDir "\..\templates"
        names := []
        loop files folder "\*.png"
            names.Push(A_LoopFileName)
        AssertEq(names.Length, ButtonFiles.SHA256.Count, "templates vs ButtonFiles.SHA256")
        for fileName in names {
            Assert(ButtonFiles.SHA256.Has(fileName), fileName " isn't in src\ButtonFiles.ahk")
            AssertEq(Sha256.File(folder "\" fileName), ButtonFiles.SHA256[fileName], fileName)
        }
    }

    static Test_every_required_button_has_an_image() {
        AssertEq(Buttons.Missing(Buttons.Load(A_ScriptDir "\..\templates")), [])
    }

    ; A copy that doesn't match this version's checksum is never used, even
    ; when a fresh one can't be downloaded.
    static Test_button_images_that_fail_their_checksum_are_not_used() {
        folder := App.Dir "\buttons"
        DirCreate(folder)
        loop files A_ScriptDir "\..\templates\*.png"
            FileCopy(A_LoopFilePath, folder "\" A_LoopFileName)
        FileCopy(A_ScriptDir "\..\templates\admin_yes.png", folder "\server_row.png", true)  ; the wrong picture
        Patches.Set(Http, "Download", ThrowOffline)
        missing := Buttons.Fetch(folder, ButtonFiles.SHA256, "main")
        AssertEq(missing, ["server_row.png"])
        Assert(!FileExist(folder "\server_row.png"), "the wrong copy is still there")
        crops := Buttons.Load(folder, ButtonFiles.SHA256)
        cuts := []
        for crop in crops["server_row"]
            cuts.Push(crop.cut)
        AssertEq(cuts, [1080, 2160])  ; the plain 1440p one is gone; the others still load
        ; and a copy changed after it was checked is skipped when loading
        FileCopy(A_ScriptDir "\..\templates\admin_yes.png", folder "\create_unit.png", true)
        AssertEq(Buttons.Load(folder, ButtonFiles.SHA256)["create_unit"].Length, 1)
        AssertEq(Buttons.Load(folder, ButtonFiles.SHA256)["create_unit"][1].cut, 1080)
    }

    ; The window's fonts come down all at once, within a time limit in all: a
    ; download only stays if its checksum matches, an old copy that doesn't
    ; goes, and one that hasn't come by then is stopped.
    static Test_files_fetched_at_once_are_checked_and_late_ones_stopped() {
        folder := App.Dir "\fetch"
        DirCreate(folder)
        files := Map("a.ttf", Sha256.Text("font a"), "b.ttf", Sha256.Text("font b"), "c.ttf", Sha256.Text("font c"), "d.ttf", Sha256.Text("font d"))
        FileAppend("font d", folder "\d.ttf", "UTF-8-RAW")  ; already here
        FileAppend("old b", folder "\b.ttf", "UTF-8-RAW")   ; an old copy
        answers := Map("a.ttf", FakeResponse("font a"), "b.ttf", FakeResponse("not b"), "c.ttf", FakeResponse("font c", false))
        asked := []
        start(this, url, accept, timeout, async) {
            asked.Push([url, async])
            return answers[RegExReplace(url, ".*/")]
        }
        Patches.Set(Http, "Start", start)
        Logs.capture := []
        t0 := A_TickCount
        missing := RepoFiles.FetchAtOnce(folder, files, "abc123", "assets/fonts", "font", 0.4)
        took := A_TickCount - t0
        base := "https://raw.githubusercontent.com/" App.REPO "/abc123/assets/fonts/"
        AssertEq(asked, [[base "a.ttf", true], [base "b.ttf", true], [base "c.ttf", true]])
        AssertEq(missing, ["b.ttf", "c.ttf"])
        AssertEq(FileRead(folder "\a.ttf"), "font a")
        AssertEq(FileRead(folder "\d.ttf"), "font d")
        Assert(!FileExist(folder "\b.ttf"), "the old b is still there")
        Assert(!FileExist(folder "\c.ttf"), "c is there")
        Assert(answers["c.ttf"].aborted, "the late download wasn't stopped")
        Assert(took >= 400 && took < 3000, "took " took " ms")
        Assert(!FileExist(folder "\*.part"), "a .part file was left")
        AssertEq(Logs.capture.Length, 2)
        Assert(InStr(Logs.capture[1], "b.ttf: the download isn't the right file"), Logs.capture[1])
        Assert(InStr(Logs.capture[2], "c.ttf: no answer in 0.4 seconds"), Logs.capture[2])
    }

    ; The window tries GitHub for fonts it lacks only every few hours once a
    ; try has failed; a seeding run always tries, and a try that works clears it.
    static Test_window_leaves_github_alone_for_a_while_after_fonts_fail() {
        folder := App.Dir "\fonts", note := folder "\download-failed.txt"
        Patches.Value(Look, "FontFolder", folder)
        tries := [], result := ["Inter.ttf"]
        Patches.Set(RepoFiles, "FetchAtOnce", (this, dir, files, ref, path, what, wait) => (DirCreate(dir), tries.Push(wait), result))
        Look.GetFonts(Look.FONT_WAIT, true)  ; the window, offline
        AssertEq(tries, [3])
        Assert(FileExist(note), "no note of the failure")
        Look.GetFonts(Look.FONT_WAIT, true)  ; opened again soon after
        AssertEq(tries, [3], "the window tried again at once")
        Look.GetFonts(30)  ; a seeding run
        AssertEq(tries, [3, 30])
        out := FileOpen(note, "w"), out.Write(DateAdd(A_NowUTC, -(Look.FONT_RETRY_HOURS + 1), "Hours")), out.Close()
        Look.GetFonts(Look.FONT_WAIT, true)  ; hours later
        AssertEq(tries, [3, 30, 3])
        out := FileOpen(note, "w"), out.Write("not a time"), out.Close()
        Look.GetFonts(Look.FONT_WAIT, true)
        AssertEq(tries.Length, 4, "a broken note stopped it trying")
        result := []  ; online again, and the daily run gets them
        Look.GetFonts(30)
        AssertEq(tries.Length, 5)
        Assert(!FileExist(note), "the note is still there")
        Look.GetFonts(Look.FONT_WAIT, true)
        AssertEq(tries.Length, 6)
    }

    ; In a built exe the window waits FONT_WAIT seconds for fonts and, once
    ; that has failed, leaves GitHub alone; a seeding run has time to wait.
    static Test_built_exe_window_and_run_get_fonts_their_own_way() {
        Patches.Value(App, "Built", true)
        Patches.Value(Look, "FontFolder", App.Dir "\fonts")
        tries := []
        Patches.Set(RepoFiles, "FetchAtOnce", (this, dir, files, ref, path, what, wait) => (DirCreate(dir), tries.Push(wait), ["Inter.ttf"]))
        AssertEq(Look.LoadFonts(), 0)  ; the window, offline
        AssertEq(Look.LoadFonts(), 0)  ; opened again soon after
        AssertEq(tries, [Look.FONT_WAIT])
        Patches.Value(Buttons, "Folder", A_ScriptDir "\..\templates")
        Patches.Set(Buttons, "Fetch", (*) => [])
        LoadButtons()  ; a seeding run
        AssertEq(tries, [Look.FONT_WAIT, 30])
    }

    static Test_button_file_names() {
        info := Buttons.Parse("server_row.1080p.png")
        AssertEq([info.name, info.cut, info.tag], ["server_row", 1080, ""])
        info := Buttons.Parse("roles_confirm.title.png")
        AssertEq([info.name, info.cut, info.tag], ["roles_confirm", 1440, "title"])
        info := Buttons.Parse("admin_yes.png")
        AssertEq([info.name, info.cut, info.tag], ["admin_yes", 1440, ""])
    }

    static Test_players_own_images_replace_a_buttons_images() {
        base := Map("a", [1, 2], "b", [3])
        merged := Buttons.Merge(base, Map("a", [9]))
        AssertEq(merged["a"], [9])
        AssertEq(merged["b"], [3])
    }

    static Test_sha256() {
        AssertEq(Sha256.Text("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        AssertEq(Sha256.File(App.Dir "\missing"), "")
    }

    static Test_seed_lock_is_free_here() {
        Assert(!SeedLock.HeldElsewhere())
        Assert(SeedLock.Claim())
        try {
            Assert(SeedLock.HeldElsewhere())  ; this process has it now
            Assert(!SeedLock.Claim(), "claimed twice")
        } finally {
            SeedLock.Release()
        }
        Assert(!SeedLock.HeldElsewhere())
        AssertEq(SeedLock.Runs(), [])
    }
}
