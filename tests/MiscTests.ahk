; Settings, server stats, the daily task's XML, the command line and helpers
; (partly ported from the first SynSeeder's tests).

; The live Syndicate stats page, trimmed (2026-10-24).
LIVE_STATS := '{"result": {"name": {"name": "Syndicate | Competitive Server | Discord.gg/syn-hll | Radical Gaming Network", "short_name": "Syn Nam"}, "player_count": 11, "max_player_count": 100, "player_count_by_team": {"allied": 6, "axis": 5}, "time_remaining": 2327.0, "match_time": 5400}, "failed": false}'

TaskField(xml, tag) => RegExMatch(xml, "<" tag ">([^<]*)</" tag ">", &m) ? m[1] : ""

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

    static Test_json_rejects_broken_text() {
        for text in ["", "{", "[1,]", '{"a" 1}', "tru", '"open', "1 2"] {
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
