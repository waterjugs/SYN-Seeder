; Things every part of SynSeeder uses: where it keeps its files, the log, and
; a clock that a stop request can interrupt.

class App {
    static NAME := "SynSeeder"
    static VERSION := "1.1.0"  ; keep in step with the ;@Ahk2Exe-SetVersion line in SynSeeder.ahk
    static REPO := "waterjugs/SYN-Seeder"
    static TERMS_URL := "https://github.com/waterjugs/SYN-Seeder/blob/main/TERMS.md"
    static PRIVACY_URL := "https://github.com/waterjugs/SYN-Seeder/blob/main/PRIVACY.md"

    static dirOverride := ""  ; tests point App.Dir somewhere else

    ; %APPDATA%\SynSeeder: settings, the log, debug screenshots and players' own button images.
    static Dir {
        get {
            if App.dirOverride != "" {
                DirCreate(App.dirOverride)
                return App.dirOverride
            }
            base := EnvGet("APPDATA")
            path := (base != "" ? base : A_MyDocuments) "\" App.NAME
            DirCreate(path)
            return path
        }
    }

    ; %LOCALAPPDATA%\SynSeeder: the copy of SynSeeder.exe the daily task starts,
    ; and the downloaded button images.
    static InstallDir {
        get {
            base := EnvGet("LOCALAPPDATA")
            return (base != "" ? base : A_MyDocuments) "\" App.NAME
        }
    }

    ; "1.2.3" as [1, 2, 3], or "" if it isn't a version number. A leading v is fine.
    static ParseVersion(text) {
        if !RegExMatch(Trim(text), "^v?(\d+)\.(\d+)\.(\d+)$", &m)
            return ""
        return [Integer(m[1]), Integer(m[2]), Integer(m[3])]
    }

    ; -1, 0 or 1 as version ``a`` is older than, the same as or newer than ``b``.
    static CompareVersions(a, b) {
        loop 3
            if a[A_Index] != b[A_Index]
                return a[A_Index] < b[A_Index] ? -1 : 1
        return 0
    }
}

; The log: %APPDATA%\SynSeeder\seeder.log, one line per event.
class Logs {
    static path := ""
    static echo := false  ; also print each line (tests and CI)
    static capture := ""  ; an Array to collect lines in (tests)
    static MAX_BYTES := 5 * 1024 * 1024

    static Open(path := "") {
        Logs.path := path != "" ? path : App.Dir "\seeder.log"
        ; keep one older log next to it rather than letting it grow forever
        try {
            if FileExist(Logs.path) && FileGetSize(Logs.path) > Logs.MAX_BYTES
                FileMove(Logs.path, RegExReplace(Logs.path, "\.log$", ".old.log"), true)
        }
    }

    static Info(message) => Logs.Write("INFO", message)
    static Warning(message) => Logs.Write("WARNING", message)
    static Error(message) => Logs.Write("ERROR", message)

    ; An error with where it happened, for crashes.
    static Exception(message, err) {
        detail := Type(err) ": " err.Message
        if err.HasProp("Extra") && err.Extra != ""
            detail .= " (" err.Extra ")"
        Logs.Write("ERROR", message "`n" detail "`n" err.Stack)
    }

    static Write(level, message) {
        line := FormatTime(, "yyyy-MM-dd HH:mm:ss") " " level " " message "`n"
        if Logs.echo
            try FileAppend(line, "*", "UTF-8")
        if Logs.capture is Array
            Logs.capture.Push(level " " message)
        if Logs.path = ""
            return
        loop 3 {  ; another SynSeeder may be writing at the same moment
            try {
                FileAppend(line, Logs.path, "UTF-8")
                return
            }
            Sleep(20)
        }
    }
}

; Thrown when the player asks a run to stop (Ctrl+Alt+End or Stop seeding).
class SeedStopped extends Error {
}

; Time for the seeding run, in seconds. Sleep wakes up early and throws
; SeedStopped when ``ShouldStop`` says so (it's checked every 100 ms).
class SeedClock {
    __New(shouldStop := "") {
        this.shouldStop := shouldStop
    }

    Now() => DllCall("GetTickCount64", "Int64") / 1000

    Sleep(seconds) {
        this.Check()
        wake := DllCall("GetTickCount64", "Int64") + Round(seconds * 1000)
        loop {
            left := wake - DllCall("GetTickCount64", "Int64")
            if left <= 0
                break
            Sleep(Min(left, 100))
            this.Check()
        }
    }

    Check() {
        if this.shouldStop && (this.shouldStop)()
            throw SeedStopped("Stopped")
    }
}

; Quotes a program argument the way Windows programs read them back.
QuoteArg(arg) {
    if arg != "" && !RegExMatch(arg, '[\s"]')
        return arg
    out := '"', slashes := 0
    loop parse arg {
        if A_LoopField = "\" {
            slashes++
            continue
        }
        if A_LoopField = '"' {
            loop slashes * 2 + 1
                out .= "\"
            out .= '"'
        } else {
            loop slashes
                out .= "\"
            out .= A_LoopField
        }
        slashes := 0
    }
    loop slashes * 2
        out .= "\"
    return out '"'
}

; Joins an array's items with ``sep``.
JoinList(items, sep := ", ") {
    out := ""
    for item in items
        out .= (A_Index > 1 ? sep : "") item
    return out
}

; "4 min 5 s" for 245 seconds.
MinutesText(seconds) {
    seconds := Round(seconds)
    return seconds // 60 " min " Mod(seconds, 60) " s"
}

; ``text`` percent-encoded for a URL, every character but letters, digits and
; - . _ ~ (as UTF-8 bytes), like Python's quote(text, safe="").
UriQuote(text) {
    size := StrPut(text, "UTF-8") - 1
    data := Buffer(size + 1)
    StrPut(text, data, "UTF-8")
    out := ""
    loop size {
        byte := NumGet(data, A_Index - 1, "UChar")
        if (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
            || byte = 0x2D || byte = 0x2E || byte = 0x5F || byte = 0x7E
            out .= Chr(byte)
        else
            out .= Format("%{:02X}", byte)
    }
    return out
}

; Undoes percent-encoding (%3A -> :), reading the bytes as UTF-8. A % that
; isn't followed by two hex digits stays as it is.
UriUnquote(text) {
    if !InStr(text, "%")
        return text
    size := StrPut(text, "UTF-8") - 1
    data := Buffer(size + 1)
    StrPut(text, data, "UTF-8")
    out := Buffer(size + 1)
    i := 0, n := 0
    while i < size {
        byte := NumGet(data, i, "UChar")
        if byte = 0x25 && i + 2 < size {
            hex := StrGet(data.Ptr + i + 1, 2, "CP0")
            if RegExMatch(hex, "^[0-9A-Fa-f]{2}$") {
                byte := Integer("0x" hex)
                i += 2
            }
        }
        NumPut("UChar", byte, out, n++)
        i++
    }
    return StrGet(out, n, "UTF-8")
}
