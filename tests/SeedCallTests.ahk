; Seed when pinged: the once-a-minute check, on a fake PC. Nothing goes
; online, no question is shown and no run starts, except in the tests of the
; question window itself and of reading a (fake) answer.

; A PC at 14:00 on 23 November 2026 (UTC-5) with Seed when pinged on, unlocked,
; no game or run, nobody at it for 10 minutes and nothing full screen. The
; service answers with each of ``replies`` in turn, then repeats the last
; (an Error stands for not reaching it). It records what the check did.
class FakeCallEnv {
    __New(replies*) {
        this.settings := SeederConfig()
        this.settings.seed_when_pinged := true
        this.badConfig := false
        this.local := "20261123140000", this.utc := "20261123190000", this.ms := 5000000
        this.isUnlocked := true, this.gameIsOpen := false, this.runGoing := false
        this.idle := 600, this.full := false
        this.replies := replies.Length ? replies : [{call: "", age: 0}]
        this.fetches := 0
        this.wait := 42, this.most := ""
        this.paused := [], this.onPause := ""
        this.asked := [], this.onAsk := "", this.answer := "yes"
        this.started := 0, this.startError := ""
    }

    Config() {
        if this.badConfig
            throw ValueError("broken")
        return this.settings
    }
    NowLocal() => this.local
    NowUtc() => this.utc
    Ticks() => this.ms
    Unlocked() => this.isUnlocked
    GameOpen(config) => this.gameIsOpen
    Seeding() => this.runGoing
    IdleSeconds() => this.idle
    FullScreen() => this.full

    Fetch() {
        this.fetches++
        reply := this.replies.Length > 1 ? this.replies.RemoveAt(1) : this.replies[1]
        if reply is Error
            throw reply
        return reply
    }

    RandomWait(most) {
        this.most := most
        return this.wait
    }

    Pause(seconds) {
        this.paused.Push(seconds)
        this.Advance(seconds)
        if this.onPause
            (this.onPause)(this)
    }

    Ask(seconds, onTop, still) {
        this.asked.Push([seconds, onTop])
        if this.onAsk
            (this.onAsk)(this)
        return this.answer
    }

    Start() {
        if this.startError
            throw Error(this.startError)
        this.started++
    }

    ; Time passes: ``seconds`` later on every clock.
    Advance(seconds) {
        this.ms += seconds * 1000
        this.local := DateAdd(this.local, seconds, "Seconds"), this.utc := DateAdd(this.utc, seconds, "Seconds")
    }
}

; A FakeResponse that answers with another status.
class StatusResponse extends FakeResponse {
    __New(status, text) {
        super.__New(text)
        this.code := status
    }
    Status => this.code
    StatusText => "Service Unavailable"
}

CALL_A := "0123456789abcdef0123456789abcdef"
CALL_B := "fedcba9876543210fedcba9876543210"

class SeedCallTests {
    static Call(id := CALL_A, age := 30) => {call: id, age: age}

    ; Runs a check with log lines captured. Returns its exit code.
    static Check(env) {
        if !(Logs.capture is Array)
            Logs.capture := []
        return SeedCalls.Check(env)
    }

    static State() => SeedCalls.LoadState()

    ; When the check does nothing at all

    static Test_off_does_nothing() {
        for value in [false, "true", "yes", 2] {  ; only a real true turns it on
            env := FakeCallEnv(SeedCallTests.Call())
            env.settings.seed_when_pinged := value
            Logs.capture := []
            AssertEq(SeedCallTests.Check(env), 0)
            AssertEq([env.fetches, env.started, Logs.capture], [0, 0, []], "seed_when_pinged " value)
            Assert(!FileExist(SeedCalls.StatePath), "seed-calls.json made with the box off")
        }
    }

    static Test_broken_settings_do_nothing_quietly() {
        env := FakeCallEnv(SeedCallTests.Call())
        env.badConfig := true
        Logs.capture := []
        AssertEq(SeedCallTests.Check(env), 0)
        AssertEq([env.fetches, Logs.capture], [0, []])
    }

    static Test_nothing_goes_online_outside_hours_or_while_busy() {
        cases := [["outside hours", (e) => e.local := "20261123230000"],
            ["early", (e) => e.local := "20261123075959"],
            ["locked", (e) => e.isUnlocked := false],
            ["game open", (e) => e.gameIsOpen := true],
            ["a run going", (e) => e.runGoing := true]]
        for item in cases {
            env := FakeCallEnv(SeedCallTests.Call())
            item[2](env)
            Logs.capture := []
            SeedCallTests.Check(env)
            AssertEq([env.fetches, env.started, Logs.capture], [0, 0, []], item[1])
        }
    }

    static Test_no_call_leaves_no_trace() {
        env := FakeCallEnv()
        Logs.capture := []
        AssertEq(SeedCallTests.Check(env), 0)
        AssertEq([env.fetches, env.started, env.asked, Logs.capture], [1, 0, [], []])
        Assert(!FileExist(SeedCalls.StatePath))
    }

    static Test_hours() {
        at(hhmm) => "20261123" hhmm "00"
        for item in [["08:00", "23:00", "0800", true], ["08:00", "23:00", "2259", true], ["08:00", "23:00", "2300", false],
            ["08:00", "23:00", "0759", false], ["22:00", "02:00", "2330", true], ["22:00", "02:00", "0159", true],
            ["22:00", "02:00", "0200", false], ["22:00", "02:00", "1200", false], ["08:00", "00:00", "2359", true],
            ["08:00", "08:00", "0300", true], ["8:30", "9:15", "0914", true], ["8:30", "9:15", "0829", false],
            ["soon", "23:00", "0759", false], ["soon", "23:00", "0800", true], ["25:00", "23:60", "2300", false]]
            AssertEq(SeedCalls.InHours(item[1], item[2], at(item[3])), item[4], item[1] " to " item[2] " at " item[3])
    }

    ; A new call

    static Test_free_pc_starts_a_run_after_a_random_wait() {
        env := FakeCallEnv(SeedCallTests.Call(CALL_A, 30))
        AssertEq(SeedCallTests.Check(env), 0)
        AssertEq([env.most, env.paused, env.asked, env.started], [180, [42], [], 1])
        state := SeedCallTests.State()
        AssertEq([state.last_call, state.last_run, state.runs_today, state.retry_after], [CALL_A, "20261123190042", 1, ""])
        AssertEq(Logs.capture, ["INFO Seed call: nobody is using the PC, so a run starts in 42 s",
            "INFO Seed call: started a seeding run (1 of 3 today)"])
    }

    static Test_the_wait_leaves_time_to_start() {
        env := FakeCallEnv(SeedCallTests.Call(CALL_A, 870))  ; 30 s left
        env.wait := 150
        SeedCallTests.Check(env)
        AssertEq([env.paused, env.started], [[20], 1])
    }

    static Test_a_call_is_acted_on_once() {
        env := FakeCallEnv(SeedCallTests.Call())
        env.idle := 5, env.answer := "you said not now"
        SeedCallTests.Check(env)
        env.Advance(60)
        SeedCallTests.Check(env)
        AssertEq([env.fetches, env.asked.Length, env.started], [2, 1, 0])
        AssertEq(SeedCallTests.State().last_call, CALL_A)
        AssertEq(Logs.capture, ["INFO Seed call: asking first, because someone is using the PC",
            "INFO Seed call: no run, because you said not now"])
    }

    static Test_someone_at_the_pc_is_asked_first() {
        env := FakeCallEnv(SeedCallTests.Call(CALL_A, 30))
        env.idle := 299
        SeedCallTests.Check(env)
        AssertEq([env.paused, env.asked, env.started], [[], [[300, true]], 1])
        AssertEq(SeedCallTests.State().runs_today, 1)
        AssertEq(Logs.capture, ["INFO Seed call: asking first, because someone is using the PC",
            "INFO Seed call: started a seeding run (1 of 3 today)"])
    }

    ; A full-screen game or film: asked too, in a window that doesn't stay on top of it.
    static Test_full_screen_is_asked_first() {
        env := FakeCallEnv(SeedCallTests.Call(CALL_A, 700))
        env.full := true
        SeedCallTests.Check(env)
        AssertEq([env.paused, env.asked, env.started], [[], [[200, false]], 1])
        AssertEq(Logs.capture[1], "INFO Seed call: asking first, because something is full screen")
    }

    static Test_no_answer_starts_nothing() {
        env := FakeCallEnv(SeedCallTests.Call())
        env.idle := 10, env.answer := "nobody answered in time"
        SeedCallTests.Check(env)
        AssertEq(env.started, 0)
        state := SeedCallTests.State()
        AssertEq([state.last_call, state.last_run, state.runs_today], [CALL_A, "", 0])
        AssertEq(Logs.capture[2], "INFO Seed call: no run, because nobody answered in time")
    }

    static Test_after_the_wait_it_checks_again() {
        cases := [["the game is open", (e) => e.gameIsOpen := true],
            ["a run is already going", (e) => e.runGoing := true],
            ["the PC is locked", (e) => e.isUnlocked := false],
            ["Seed when pinged is off", (e) => e.settings.seed_when_pinged := false],
            ["it's outside your hours", (e) => e.local := "20261123230005"]]
        for item in cases {
            try FileDelete(SeedCalls.StatePath)  ; each case is a new call
            env := FakeCallEnv(SeedCallTests.Call())
            env.onPause := item[2]
            Logs.capture := []
            SeedCallTests.Check(env)
            AssertEq([env.started, env.asked], [0, []], item[1])
            AssertEq(Logs.capture[2], "INFO Seed call: skipped, because " item[1])
        }
    }

    static Test_someone_back_after_the_wait_is_asked() {
        env := FakeCallEnv(SeedCallTests.Call(CALL_A, 30))
        env.onPause := (e) => e.idle := 3
        SeedCallTests.Check(env)
        AssertEq([env.asked, env.started], [[[300, true]], 1])
        AssertEq(Logs.capture[2], "INFO Seed call: asking first, because someone is using the PC now")
    }

    ; A "yes" counts only if a run may still start: the call is live, the hours
    ; haven't ended, the box is still ticked, and so on.
    static Test_a_late_yes_does_nothing() {
        cases := [["the call has ended", 880, (e) => e.Advance(25)],
            ["it's outside your hours", 30, (e) => e.local := "20261123230000"],
            ["Seed when pinged is off", 30, (e) => e.settings.seed_when_pinged := false],
            ["the game is open", 30, (e) => e.gameIsOpen := true]]
        for item in cases {
            try FileDelete(SeedCalls.StatePath)
            env := FakeCallEnv(SeedCallTests.Call(CALL_A, item[2]))
            env.idle := 10, env.onAsk := item[3]
            Logs.capture := []
            SeedCallTests.Check(env)
            AssertEq(env.started, 0, item[1])
            AssertEq(Logs.capture[2], "INFO Seed call: skipped, because " item[1])
        }
        FileDelete(SeedCalls.StatePath)
        env := FakeCallEnv(SeedCallTests.Call(CALL_A, 880))
        env.idle := 10
        SeedCallTests.Check(env)
        AssertEq(env.asked, [[20, true]], "asked only while the call lasts")
    }

    static Test_a_run_that_wont_start_is_logged() {
        env := FakeCallEnv(SeedCallTests.Call())
        env.startError := "Couldn't copy SynSeeder.exe"
        AssertEq(SeedCallTests.Check(env), 1)
        Assert(InStr(Logs.capture[2], "ERROR Seed call: couldn't start seeding") = 1, Logs.capture[2])
        AssertEq(SeedCallTests.State().runs_today, 1)  ; counted all the same: it's never tried twice for one call
    }

    ; Limits

    static Test_three_runs_a_day_at_most() {
        env := FakeCallEnv(SeedCallTests.Call(CALL_B))
        SeedCalls.SaveState({last_call: CALL_A, last_run: "20261123150000", runs_today: 3, retry_after: ""})  ; 10:00 local
        SeedCallTests.Check(env)
        AssertEq(env.fetches, 0)
        env.local := "20261124090000", env.utc := "20261124140000"  ; the next day
        SeedCallTests.Check(env)
        AssertEq([env.fetches, env.started, SeedCallTests.State().runs_today], [1, 1, 1])
    }

    ; "Today" is the PC's own day, not UTC's.
    static Test_runs_today_by_the_pcs_calendar() {
        env := FakeCallEnv()
        state := {last_call: "", last_run: "20261124030000", runs_today: 2, retry_after: ""}  ; 22:00 on the 23rd at UTC-5
        env.local := "20261123233000", env.utc := "20261124043000"
        AssertEq(SeedCalls.RunsToday(state, env), 2)
        env.local := "20261124003000", env.utc := "20261124053000"
        AssertEq(SeedCalls.RunsToday(state, env), 0)
    }

    static Test_thirty_minutes_between_runs() {
        for item in [["20261123184100", 0], ["20261123183000", 1], ["20261123191500", 0], ["20261123220000", 1]] {
            env := FakeCallEnv(SeedCallTests.Call(CALL_B))
            SeedCalls.SaveState({last_call: CALL_A, last_run: item[1], runs_today: 1, retry_after: ""})
            SeedCallTests.Check(env)
            AssertEq(env.fetches, item[2], "last run at " item[1] " UTC, now 19:00")  ; a run "ahead" means the clock went back
        }
    }

    static Test_a_failed_check_waits_before_trying_again() {
        env := FakeCallEnv(Error("offline"), Error("still offline"), {call: "", age: 0})
        Logs.capture := []
        SeedCallTests.Check(env)
        AssertEq(SeedCallTests.State().retry_after, "20261123190500")
        AssertEq(Logs.capture, ["WARNING Seed call: couldn't check for one (offline); trying again in a few minutes"])
        env.Advance(240)
        SeedCallTests.Check(env)
        AssertEq(env.fetches, 1, "tried again within 5 minutes")
        env.Advance(60)
        SeedCallTests.Check(env)
        AssertEq([env.fetches, SeedCallTests.State().retry_after], [2, "20261123192000"])
        AssertEq(Logs.capture.Length, 1, "logged again while it's still down")
        env.Advance(900)
        SeedCallTests.Check(env)
        AssertEq([env.fetches, SeedCallTests.State().retry_after], [3, ""])
    }

    ; A retry time far off came from the clock going back: it's ignored.
    static Test_a_far_off_retry_time_is_ignored() {
        env := FakeCallEnv()
        SeedCalls.SaveState({last_call: "", last_run: "", runs_today: 0, retry_after: "20261124190000"})
        SeedCallTests.Check(env)
        AssertEq(env.fetches, 1)
    }

    ; The service's answer

    static Test_answers_are_read_strictly() {
        AssertEq(SeedCalls.Parse('{"call":null}').call, "")
        reply := SeedCalls.Parse('{"call":"' CALL_A '","age":899}')
        AssertEq([reply.call, reply.age], [CALL_A, 899])
        for text in ['{"call":"' StrUpper(CALL_A) '","age":1}', '{"call":"' SubStr(CALL_A, 2) '","age":1}',
            '{"call":"' CALL_A '\n","age":1}', '{"call":"' CALL_A '"}', '{"call":"' CALL_A '","age":900}',
            '{"call":"' CALL_A '","age":-1}', '{"call":"' CALL_A '","age":1.5}', '{"call":"' CALL_A '","age":"1"}',
            '{"call":12,"age":1}', '{"age":1}', '[]', '"call"', '{"call":', '<html>Error 1015</html>'] {
            answer := text  ; nested functions can't see a for loop's variables
            AssertThrows(ValueError, () => SeedCalls.Parse(answer), answer)
        }
    }

    static Test_answers_are_fetched_with_a_time_limit() {
        sent := []
        answer := FakeResponse('{"call":"' CALL_A '","age":12}')
        Patches.Set(SeedCalls, "_Send", (this, url) => (sent.Push(url), answer))
        reply := SeedCalls.Fetch()
        AssertEq([reply.call, reply.age, sent], [CALL_A, 12, [SeedCalls.URL]])
        answer := FakeResponse('{"call":null}', false)  ; never answers
        err := AssertThrows(Error, () => SeedCalls.Fetch())
        AssertEq([err.Message, answer.aborted], ["no answer in 5 seconds", true])
        answer := FakeResponse('{"call":null,"pad":"' Format("{:500}", "") '"}')
        err := AssertThrows(Error, () => SeedCalls.Fetch())
        Assert(InStr(err.Message, "too big"), err.Message)
        answer := StatusResponse(503, '{"error":"unavailable"}')
        err := AssertThrows(Error, () => SeedCalls.Fetch())
        AssertEq(err.Message, "HTTP 503 Service Unavailable")
    }

    ; Built into every copy, and must match bot\src\handler.js.
    static Test_the_service_address() {
        AssertEq(SeedCalls.URL, "https://synseeder.syn-seeder.workers.dev/seed-call")
        text := FileRead(A_ScriptDir "\..\bot\src\handler.js", "UTF-8")
        Assert(InStr(text, "if (path === '/seed-call')"), "the bot no longer answers /seed-call")
    }

    ; seed-calls.json

    static Test_the_note_holds_four_things() {
        SeedCalls.SaveState({last_call: CALL_A, last_run: "20261123190042", runs_today: 2, retry_after: ""})
        AssertEq(FileRead(SeedCalls.StatePath, "UTF-8"), '{`n  "last_call": "' CALL_A '",`n  "last_run": "2026-11-23T19:00:42Z",'
            . '`n  "runs_today": 2,`n  "retry_after": ""`n}')
        state := SeedCallTests.State()
        AssertEq([state.last_call, state.last_run, state.runs_today, state.retry_after], [CALL_A, "20261123190042", 2, ""])
        Assert(!FileExist(SeedCalls.StatePath ".tmp"))
    }

    static Test_a_broken_note_is_ignored() {
        for text in ["{not json", "[]", '{"last_call": "ABC", "last_run": "2026-13-01T00:00:00Z", "runs_today": -1, "retry_after": 5}',
            '{"last_run": "2026-11-23T19:00:42"}', '{"last_run": "2026-11-23 19:00:42Z"}'] {
            try FileDelete(SeedCalls.StatePath)
            FileAppend(text, SeedCalls.StatePath, "UTF-8-RAW")
            state := SeedCallTests.State()
            AssertEq([state.last_call, state.last_run, state.runs_today, state.retry_after], ["", "", 0, ""], text)
        }
    }

    ; The question window: no answer, or a reason to stop asking, closes it.
    static Test_the_question_closes_by_itself() {
        before := A_TickCount
        AssertEq(SeedCalls.Ask(1, false), "nobody answered in time")
        Assert(A_TickCount - before >= 900, "closed too soon")
        AssertEq(SeedCalls.Ask(30, true, () => "the game is open"), "the game is open")
        prev := DetectHiddenWindows(true)
        try
            AssertEq(WinExist("SynSeeder ahk_class AutoHotkeyGUI ahk_pid " DllCall("GetCurrentProcessId", "UInt")), 0, "the window is still there")
        finally
            DetectHiddenWindows(prev)
    }

    ; The task and command line

    static Test_calls_task_checks_every_minute_while_signed_in() {
        xml := DailyTask.CallsXml("C:\Users\A&B\SynSeeder.exe", "--check-seed-calls", "20261123140000")
        AssertEq(TaskField(xml, "StartBoundary"), "2026-11-23T14:00:00")
        AssertEq(TaskField(xml, "Interval"), "PT1M")
        Assert(!InStr(xml, "<Duration>"), "a repetition with a Duration stops")
        Assert(!InStr(xml, "<CalendarTrigger>") && !InStr(xml, "<LogonTrigger>"), "one trigger only: two would check twice a minute")
        for item in [["LogonType", "InteractiveToken"], ["RunLevel", "LeastPrivilege"], ["MultipleInstancesPolicy", "IgnoreNew"],
            ["StartWhenAvailable", "false"], ["DisallowStartIfOnBatteries", "false"], ["StopIfGoingOnBatteries", "false"],
            ["ExecutionTimeLimit", "PT10M"], ["Command", "C:\Users\A&amp;B\SynSeeder.exe"], ["Arguments", "--check-seed-calls"]]
            AssertEq(TaskField(xml, item[1]), item[2], item[1])
        Assert(SubStr(xml, 1, 39) == '<?xml version="1.0" encoding="UTF-16"?>', SubStr(xml, 1, 60))
        AssertEq(DailyTask.CALLS_NAME, "SynSeeder seed calls")  ; the privacy policy gives this name
    }

    static Test_script_calls_command_runs_the_script() {
        AssertEq(DailyTask.CallsCommand(), [A_AhkPath, QuoteArg(A_ScriptFullPath) " --check-seed-calls"])
    }

    static Test_command_line_check() {
        opts := ParseArgs(["--check-seed-calls"])
        AssertEq([opts.checkSeedCalls, opts.seed, opts.passOn, opts.unknown], [true, false, "", []])
        Assert(!ParseArgs([]).checkSeedCalls)
    }
}
