; Settings, stored as JSON in %APPDATA%\SynSeeder\config.json. Names and
; defaults are the same as the first (Python) SynSeeder's, so its settings carry over.

class SeederConfig {
    ; [name, default] in the order they're saved
    static FIELDS := [
        ; the server to seed
        ["server_name", "Syndicate | Competitive Server"],
        ["server_search", "syndicate"],  ; lowercase: typed key by key
        ["crcon_url", "https://syn-stats-nam.radicalgamingstats.com/api/get_public_info"],
        ["seeded_threshold", 80],
        ; once seeded, wait a random 0 to this many minutes before leaving, so
        ; seeders don't all leave at once (0 leaves straight away)
        ["leave_delay_minutes", 10],
        ; how the game is started: "steam" or "epic"
        ["launcher", "steam"],
        ["steam_app_id", 3079210],
        ["epic_app_name", ""],  ; namespace:item:app or AppName; found automatically when empty
        ["process_name", "HLLVietnam-Win64-Shipping.exe"],
        ; daily start time (24h, local time) used by the scheduled task
        ["start_time", "07:00"],
        ; release builds install newer GitHub releases before a run
        ["auto_update", true],
        ; Seed when pinged: a seed called with the Discord bot starts a run,
        ; between these hours (24h, local time; the same hour twice is all day)
        ["seed_when_pinged", false],
        ["pinged_from", "08:00"],
        ["pinged_until", "23:00"],
        ; timings, in seconds unless noted
        ["poll_seconds", 30],
        ["anti_afk_seconds", 60],
        ["launch_timeout", 300],
        ["load_timeout", 240],
        ["max_restarts", 3],
        ["max_minutes", 240]]
    static BOOLEANS := ["auto_update", "seed_when_pinged"]

    __New() {
        for field in SeederConfig.FIELDS
            this.%field[1]% := field[2]
        this.ignored := []  ; settings the file had that couldn't be used (see Load)
    }

    static DefaultPath => App.Dir "\config.json"

    ; The saved settings, or the defaults if there are none. Throws if the file
    ; can't be read or isn't JSON; settings it doesn't know are ignored. A
    ; setting whose value can't be used (see Valid) keeps its default, and its
    ; name goes in ``ignored`` for whoever wants to say so: nothing is logged
    ; here, since the seed-call check loads the settings once a minute.
    static Load(path := "") {
        path := path != "" ? path : SeederConfig.DefaultPath
        config := SeederConfig()
        if !FileExist(path)
            return config
        data := Json.Load(FileRead(path, "UTF-8"))
        if !(data is Map)
            throw ValueError("the settings aren't a JSON object")
        for field in SeederConfig.FIELDS {
            name := field[1]
            if !data.Has(name)
                continue
            if SeederConfig.Valid(name, data[name])
                config.%name% := data[name]
            else
                config.ignored.Push(name)
        }
        return config
    }

    ; True if ``value``, as read from the file, can be used for the setting
    ; ``name``. The file can be edited by hand, and a slip in it mustn't break
    ; a run halfway, end every run at once, or have one ask the stats page
    ; over and over without a pause.
    static Valid(name, value) {
        inRange(low, high) => (value is Integer || value is Float) && value >= low && value <= high
        wholeIn(low, high) => value is Integer && value >= low && value <= high
        switch name, true {
            case "server_name", "launcher", "epic_app_name", "process_name":
                return value is String
            case "server_search":
                return value is String && value != ""
            case "crcon_url":
                return value is String && RegExMatch(value, "i)^https?://\S+$") > 0
            case "start_time", "pinged_from", "pinged_until":
                return value is String && SeedCalls.MinuteOfDay(value, -1) >= 0
            case "auto_update", "seed_when_pinged":  ; true and false are read as 1 and 0
                return wholeIn(0, 1)
            case "seeded_threshold":
                return wholeIn(1, 1000)
            case "steam_app_id":
                return wholeIn(1, 0xFFFFFFFF)
            case "max_restarts":
                return wholeIn(0, 20)
            case "leave_delay_minutes":
                return inRange(0, 24 * 60)
            case "poll_seconds", "anti_afk_seconds":
                return inRange(5, 3600)
            case "launch_timeout", "load_timeout":
                return inRange(10, 3600)
            case "max_minutes":
                return inRange(1, 24 * 60)
        }
        return false
    }

    Save(path := "") {
        path := path != "" ? path : SeederConfig.DefaultPath
        data := Map(), order := []
        for field in SeederConfig.FIELDS {
            name := field[1], value := this.%name%
            for flag in SeederConfig.BOOLEANS
                if flag = name
                    value := Json.Bool(value)
            data[name] := value
            order.Push(name)
        }
        text := Json.Dump(data, "  ", order)
        temp := path ".tmp"
        FileOpen(temp, "w", "UTF-8-RAW").Write(text)
        ReplaceFile(temp, path)
        return path
    }
}
