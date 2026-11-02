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
        ; timings, in seconds unless noted
        ["poll_seconds", 30],
        ["anti_afk_seconds", 60],
        ["launch_timeout", 300],
        ["load_timeout", 240],
        ["max_restarts", 3],
        ["max_minutes", 240]]
    static BOOLEANS := ["auto_update"]

    __New() {
        for field in SeederConfig.FIELDS
            this.%field[1]% := field[2]
    }

    static DefaultPath => App.Dir "\config.json"

    ; The saved settings, or the defaults if there are none. Throws if the file
    ; can't be read or isn't JSON; settings it doesn't know are ignored.
    static Load(path := "") {
        path := path != "" ? path : SeederConfig.DefaultPath
        config := SeederConfig()
        if !FileExist(path)
            return config
        data := Json.Load(FileRead(path, "UTF-8"))
        if !(data is Map)
            throw ValueError("the settings aren't a JSON object")
        for field in SeederConfig.FIELDS
            if data.Has(field[1])
                config.%field[1]% := data[field[1]]
        return config
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
        FileMove(temp, path, true)
        return path
    }
}
