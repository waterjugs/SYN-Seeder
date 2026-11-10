; Seed when pinged: the quick check that the "SynSeeder seed calls" task runs
; about once a minute while the player is signed in (SynSeeder.exe
; --check-seed-calls).
;
; Someone with the Syngineers role types /seed in the SYNDICATE Discord, and
; SynSeeder's bot (bot\ in this repository) keeps that call for 15 minutes.
; A check asks the bot's service whether there's a call and, for one it
; hasn't seen, starts the normal seeding run (--seed): by itself, after a
; random wait of up to 3 minutes, if nobody has touched the mouse or keyboard
; for 5 minutes and nothing is full screen; otherwise only if the player says
; yes when it asks.
;
; Without going online, it does nothing while the box is off, outside the
; player's hours, while the PC is locked, the game is open or a run is going,
; after 3 seed-call runs in a day, within 30 minutes of the last one, and for
; a few minutes after the service couldn't be reached. TERMS.md and
; PRIVACY.md promise all of this and what seed-calls.json holds: change them,
; at least 14 days ahead, before changing what it does.

class SeedCalls {
    ; The bot's service. Every copy of the app has this address built in, so
    ; the Worker and its workers.dev subdomain must never be renamed (bot\README.md).
    static URL := "https://synseeder.syn-seeder.workers.dev/seed-call"
    static LIFE := 900                 ; seconds a call lasts (the bot's 15 minutes)
    static IDLE := 300                 ; seconds without the mouse or keyboard before a run starts by itself
    static MAX_WAIT := 180             ; the most it waits then, at random, so PCs don't all join at once
    static ASK_SECONDS := 300          ; the most a question stays up
    static PER_DAY := 3                ; seed-call runs a day
    static GAP_MINUTES := 30           ; at least this long between two of them
    static RETRY_MINUTES := 5          ; after the service couldn't be reached...
    static RETRY_AGAIN_MINUTES := 15   ; ...and when it still can't be
    static MAX_BYTES := 512            ; an answer is far smaller: a bigger one isn't the service's
    static TIMEOUT := 5                ; seconds the service gets to answer
    ; What SHQueryUserNotificationState says while something is full screen:
    ; QUNS_BUSY, QUNS_RUNNING_D3D_FULL_SCREEN, QUNS_PRESENTATION_MODE, QUNS_APP.
    static FULL_SCREEN := [2, 3, 4, 7]

    static StatePath => App.Dir "\seed-calls.json"

    ; One check. ``env`` gives it the time, the PC's state and the call, and
    ; asks the player and starts runs (SeedCallEnv; tests pass a fake).
    ; Returns the exit code. Logs only about calls it sees and the first of
    ; a string of failed checks, so a quiet minute leaves no trace.
    static Check(env := "") {
        env := env != "" ? env : SeedCallEnv()
        if SeedCalls._Blocked(env, SeedCalls._Config(env)) != ""
            return 0
        state := SeedCalls.LoadState()
        now := env.NowUtc()
        if SeedCalls._Resting(state, now) || SeedCalls.RunsToday(state, env) >= SeedCalls.PER_DAY
            || SeedCalls._TooSoon(state, now)
            return 0
        try {
            reply := env.Fetch()
        } catch as err {
            first := state.retry_after = ""
            state.retry_after := DateAdd(now, first ? SeedCalls.RETRY_MINUTES : SeedCalls.RETRY_AGAIN_MINUTES, "Minutes")
            SeedCalls.SaveState(state)
            if first
                Logs.Warning("Seed call: couldn't check for one (" Trim(err.Message) "); trying again in a few minutes")
            return 0
        }
        if reply.call = "" || reply.call == state.last_call {
            if state.retry_after != "" {
                state.retry_after := ""
                SeedCalls.SaveState(state)
            }
            return 0
        }
        ; A new call. Noted first, so it's only ever acted on once.
        state.retry_after := "", state.last_call := reply.call
        if !SeedCalls.SaveState(state)
            return 0
        start := env.Ticks()
        left() => SeedCalls.LIFE - reply.age - (env.Ticks() - start) / 1000  ; seconds before the call ends
        still() => SeedCalls._Stopper(env, left())

        full := env.FullScreen()
        if env.IdleSeconds() >= SeedCalls.IDLE && !full {
            wait := Min(env.RandomWait(SeedCalls.MAX_WAIT), Max(0, Floor(left() - 10)))
            Logs.Info("Seed call: nobody is using the PC, so a run starts in " wait " s")
            env.Pause(wait)
            if (why := still()) != "" {
                Logs.Info("Seed call: skipped, because " why)
                return 0
            }
            full := env.FullScreen()
            if env.IdleSeconds() >= SeedCalls.IDLE && !full
                return SeedCalls._Start(env, state)
            Logs.Info("Seed call: asking first, because " (full ? "something is full screen now" : "someone is using the PC now"))
        } else {
            Logs.Info("Seed call: asking first, because " (full ? "something is full screen" : "someone is using the PC"))
        }
        seconds := Floor(Min(left(), SeedCalls.ASK_SECONDS))
        answer := seconds > 0 ? env.Ask(seconds, !full, still) : "the call has ended"
        if answer != "yes" {
            Logs.Info("Seed call: no run, because " answer)
            return 0
        }
        if (why := still()) != "" {
            Logs.Info("Seed call: skipped, because " why)
            return 0
        }
        return SeedCalls._Start(env, state)
    }

    ; The settings, or "" if the file is broken (Seed when pinged is off then).
    static _Config(env) {
        try
            return env.Config()
        catch
            return ""
    }

    ; Why there's nothing to do now, checked in the order the privacy policy
    ; gives, or "" if there may be.
    static _Blocked(env, config) {
        if config = "" || !SeedCalls.On(config)
            return "Seed when pinged is off"
        if !SeedCalls.InHours(config.pinged_from, config.pinged_until, env.NowLocal())
            return "it's outside your hours"
        if !env.Unlocked()
            return "the PC is locked"
        if env.GameOpen(config)
            return "the game is open"
        if env.Seeding()
            return "a run is already going"
        return ""
    }

    ; Why a run mustn't start now, from settings read again, or "" if it may.
    static _Stopper(env, left) {
        why := SeedCalls._Blocked(env, SeedCalls._Config(env))
        return why != "" ? why : left <= 0 ? "the call has ended" : ""
    }

    static On(config) => config.seed_when_pinged is Integer && config.seed_when_pinged = 1

    ; Records the run, then starts it.
    static _Start(env, state) {
        count := SeedCalls.RunsToday(state, env) + 1
        state.last_run := env.NowUtc(), state.runs_today := count
        if !SeedCalls.SaveState(state)
            return 0
        try {
            env.Start()
        } catch as err {
            Logs.Exception("Seed call: couldn't start seeding", err)
            return 1
        }
        Logs.Info("Seed call: started a seeding run (" count " of " SeedCalls.PER_DAY " today)")
        return 0
    }

    ; How many seed-call runs started today, by the PC's own calendar.
    static RunsToday(state, env) {
        if state.last_run = ""
            return 0
        nowLocal := env.NowLocal()
        offset := Round(DateDiff(nowLocal, env.NowUtc(), "Seconds") / 900) * 15  ; time zones go in quarter hours
        return SubStr(DateAdd(state.last_run, offset, "Minutes"), 1, 8) = SubStr(nowLocal, 1, 8) ? state.runs_today : 0
    }

    ; True within GAP_MINUTES of the last seed-call run, either way, in case the clock went back.
    static _TooSoon(state, now) => state.last_run != "" && Abs(DateDiff(now, state.last_run, "Seconds")) < SeedCalls.GAP_MINUTES * 60

    ; True while waiting to try the service again. A time further off than
    ; that wait can be came from a clock change, and is ignored.
    static _Resting(state, now) {
        if state.retry_after = ""
            return false
        ahead := DateDiff(state.retry_after, now, "Seconds")
        return ahead > 0 && ahead <= SeedCalls.RETRY_AGAIN_MINUTES * 60
    }

    ; True if ``now`` (a timestamp) is from ``from`` up to ``upTo`` ("HH:MM"),
    ; which may run past midnight. The same time twice means all day; a time
    ; that isn't one counts as its default.
    static InHours(from, upTo, now) {
        f := SeedCalls.MinuteOfDay(from, 8 * 60), u := SeedCalls.MinuteOfDay(upTo, 23 * 60)
        m := Integer(SubStr(now, 9, 2)) * 60 + Integer(SubStr(now, 11, 2))
        if f = u
            return true
        return f < u ? m >= f && m < u : m >= f || m < u
    }

    ; Minutes after midnight for "HH:MM", or ``default`` if ``text`` isn't such a time.
    static MinuteOfDay(text, default) {
        if !(text is String) || !RegExMatch(text, "D)^(\d{1,2}):(\d\d)$", &m) || m[1] > 23 || m[2] > 59
            return default
        return m[1] * 60 + m[2]
    }

    ; The service

    ; {call, age} from the service: the latest call's number and how many
    ; seconds old it is, or call "" when there's none. Throws if it can't be
    ; asked or doesn't answer as it should. Redirects aren't followed.
    static Fetch(url := "") {
        req := SeedCalls._Send(url != "" ? url : SeedCalls.URL)
        if !req.WaitForResponse(SeedCalls.TIMEOUT) {
            try req.Abort()
            throw Error("no answer in " SeedCalls.TIMEOUT " seconds")
        }
        return SeedCalls.Read(req)
    }

    ; Sends the request without waiting for the answer (tests swap this).
    static _Send(url) {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.Open("GET", url, true)
        req.Option[6] := false  ; WinHttpRequestOption_EnableRedirects
        req.SetRequestHeader("User-Agent", Http.agent)
        req.SetRequestHeader("Accept", "application/json")
        ms := SeedCalls.TIMEOUT * 1000
        req.SetTimeouts(ms, ms, ms, ms)  ; resolve, connect, send, receive
        req.Send()
        return req
    }

    static Read(req) {
        Http.Check(req)
        body := req.ResponseBody
        Http._Bytes(body, &size)
        if size > SeedCalls.MAX_BYTES
            throw Error("the answer is too big (" size " bytes)")
        return SeedCalls.Parse(Http.BodyText(req))
    }

    ; {call, age} from the answer's text. Throws ValueError unless it's
    ; {"call": null} or a call: 32 lowercase hex digits, 0 to 899 seconds old.
    static Parse(text) {
        data := Json.Load(text)
        if !(data is Map) || !data.Has("call")
            throw ValueError("the answer isn't about seed calls")
        call := data["call"]
        if call is String && call = ""
            return {call: "", age: 0}
        age := data.Has("age") ? data["age"] : ""
        if !(call is String) || !RegExMatch(call, "D)^[0-9a-f]{32}$")
            throw ValueError("the call's number isn't one")
        if !(age is Integer) || age < 0 || age >= SeedCalls.LIFE
            throw ValueError("the call's age isn't one")
        return {call: call, age: age}
    }

    ; seed-calls.json

    ; {last_call, last_run, runs_today, retry_after}: the last call acted on,
    ; when the last seed-call run started and how many started that day, and
    ; when to try the service again. Times are UTC timestamps, "" when unset.
    ; A missing or broken file, or an item that isn't right, gives the empty value.
    static LoadState(path := "") {
        path := path != "" ? path : SeedCalls.StatePath
        state := {last_call: "", last_run: "", runs_today: 0, retry_after: ""}
        try
            data := FileExist(path) ? Json.Load(FileRead(path, "UTF-8")) : ""
        catch
            return state
        if !(data is Map)
            return state
        item(name) => data.Has(name) ? data[name] : ""
        call := item("last_call")
        if call is String && RegExMatch(call, "D)^[0-9a-f]{32}$")
            state.last_call := call
        runs := item("runs_today")
        if runs is Integer && runs >= 0
            state.runs_today := runs
        state.last_run := SeedCalls.ParseStamp(item("last_run"))
        state.retry_after := SeedCalls.ParseStamp(item("retry_after"))
        return state
    }

    ; Writes the file in one go (see ReplaceFile). False, after logging why, if it can't.
    static SaveState(state, path := "") {
        path := path != "" ? path : SeedCalls.StatePath
        stamp(time) => time != "" ? FormatTime(time, "yyyy-MM-dd'T'HH:mm:ss'Z'") : ""
        data := Map("last_call", state.last_call, "last_run", stamp(state.last_run),
            "runs_today", state.runs_today, "retry_after", stamp(state.retry_after))
        try {
            temp := path ".tmp"
            FileOpen(temp, "w", "UTF-8-RAW").Write(Json.Dump(data, "  ", ["last_call", "last_run", "runs_today", "retry_after"]))
            ReplaceFile(temp, path)
            return true
        } catch as err {
            Logs.Warning("Seed call: couldn't save " path " (" err.Message ")")
            return false
        }
    }

    ; The timestamp for "2026-11-23T14:05:00Z", or "" if ``text`` isn't one.
    static ParseStamp(text) {
        if !(text is String) || !RegExMatch(text, "D)^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)Z$", &m)
            return ""
        time := m[1] m[2] m[3] m[4] m[5] m[6]
        return IsTime(time) ? time : ""
    }

    ; The PC

    ; True while Windows says a full-screen program or a presentation is on
    ; (it doesn't say which), or when it can't say.
    static FullScreenNow() {
        if DllCall("shell32\SHQueryUserNotificationState", "Int*", &state := 0, "Int") != 0  ; S_OK
            return true
        for value in SeedCalls.FULL_SCREEN
            if state = value
                return true
        return false
    }

    ; Asks whether to seed now, in a small window that doesn't take the
    ; keyboard from whatever the player is doing: it only flashes on the
    ; taskbar, and stays on top unless ``onTop`` is false (something is full
    ; screen). "Not now" has the keyboard once it's clicked. ``still`` is
    ; checked every second and says why asking is no longer worth it ("" while
    ; it is). Returns "yes", or why not after ``seconds``, a "no" or ``still``.
    static Ask(seconds, onTop, still := "") {
        answer := ""
        sayYes(*) {
            answer := "yes"
        }
        sayNo(*) {
            answer := "you said not now"
        }
        closed(*) {
            answer := "you closed the question"
        }
        g := Gui("-MinimizeBox -MaximizeBox" (onTop ? " +AlwaysOnTop" : ""), "SynSeeder")
        g.SetFont("s10", "Segoe UI")
        g.MarginX := 18, g.MarginY := 16
        g.Add("Text", "w360", "A seed was called on Discord. Start seeding now?")
        g.Add("Text", "w360 y+8", "The game will open and join the server. Leave the mouse and keyboard alone while it does.")
        ; "Not now" first, so it's the one Tab and Enter start on
        g.Add("Button", "x258 y+18 w120 Default", "Not now").OnEvent("Click", sayNo)
        g.Add("Button", "x126 yp w120", "Seed now").OnEvent("Click", sayYes)
        g.OnEvent("Close", closed)
        g.OnEvent("Escape", closed)
        g.Show("NoActivate AutoSize")
        WinApi.Flash(g.Hwnd)
        endAt := A_TickCount + seconds * 1000, lookAt := 0
        try {
            while answer = "" {
                if A_TickCount >= endAt {
                    answer := "nobody answered in time"
                    break
                }
                if still && A_TickCount >= lookAt {
                    lookAt := A_TickCount + 1000
                    if (why := still()) != "" {
                        answer := why
                        break
                    }
                }
                Sleep(100)
            }
        } finally {
            try g.Destroy()
        }
        return answer
    }
}

; What a check uses of the PC and the internet.
class SeedCallEnv {
    Config() => SeederConfig.Load()
    NowLocal() => A_Now
    NowUtc() => A_NowUTC
    Ticks() => DllCall("GetTickCount64", "Int64")  ; milliseconds
    Unlocked() => WinApi.DesktopUnlocked()
    GameOpen(config) => HllGame(config).Running()
    Seeding() => SeedLock.Running()
    IdleSeconds() => WinApi.UserIdleSeconds()
    FullScreen() => SeedCalls.FullScreenNow()
    Fetch() => SeedCalls.Fetch()
    RandomWait(most) => Random(0, most)
    Pause(seconds) => Sleep(seconds * 1000)
    Ask(seconds, onTop, still) => SeedCalls.Ask(seconds, onTop, still)

    ; Starts the normal seeding run in its own process, as Seed now does.
    Start() {
        command := DailyTask.SeedCommand()
        return SeedLock.Spawn(command[1], command[2])
    }
}
