; Stand-ins for the screen, game and clock so the seeding flow runs without
; Windows' screen or the game (ported from the first SynSeeder's tests/fakes.py).

class FakeClock {
    __New() => this.at := 0.0
    Now() => this.at
    Sleep(seconds) => this.at += seconds
    Check() => ""
}

; A FakeClock asked to stop at ``stopAt``: from then on Sleep and Check throw
; SeedStopped, as SeedClock's do.
class StoppingClock extends FakeClock {
    __New(stopAt) {
        super.__New()
        this.stopAt := stopAt
    }

    Sleep(seconds) {
        this.Check()
        this.at += seconds
        this.Check()
    }

    Check() {
        if this.at >= this.stopAt
            throw SeedStopped("Stopped")
    }
}

; ``visible`` is the set of button names on screen (a Map of name -> true).
;
; ``transitions`` maps an action to [hide, show]: a button name for a click on
; it, or "name|key" for a key pressed while that button is showing. A found
; button's position is [name, 0], so a click knows what it hit.
class FakeScreen {
    __New(transitions) {
        this.visible := Map()
        this.transitions := transitions
        this.clicks := []
        this.typed := []
        this.keys := []
        this.refreshes := 0
    }

    Show(names*) {
        this.visible := Map()
        for name in names
            this.visible[name] := true
    }

    _Apply(action) {
        change := this.transitions[action]
        for name in change[1]
            if this.visible.Has(name)
                this.visible.Delete(name)
        for name in change[2]
            this.visible[name] := true
    }

    ; True: the fake screen can always be read (see FailingScreen).
    Refresh() {
        this.refreshes++
        return true
    }

    Find(name, region := "") => this.visible.Has(name) ? [name, 0] : ""

    FindAll(name, region := "") {
        pos := this.Find(name, region)
        return pos ? [pos] : []
    }

    Click(pos) {
        name := pos[1]
        if !this.visible.Has(name)
            throw Error("clicked " name ", which isn't showing")
        this.clicks.Push(name)
        if this.transitions.Has(name)
            this._Apply(name)
    }

    TypeText(text) => this.typed.Push(text)

    Press(key) {
        this.keys.Push(key)
        for name in this.visible  ; in name order
            if this.transitions.Has(name "|" key) {
                this._Apply(name "|" key)
                return
            }
    }

    Hold(key, seconds) => this.keys.Push(key)
}

class FakeGame {
    __New(screen, running := false, launchOk := true) {
        this.screen := screen
        this.isRunning := running
        this.launchOk := launchOk
        this.launches := 0
        this.closes := 0
        this.lingered := ""
        this.focused := true
        this.locked := false
        this.userActive := false  ; with focused false: someone is using the PC
    }

    Running() => this.isRunning

    Launch(timeout := "") {
        this.launches++
        if this.launchOk {
            this.isRunning := true
            this.screen.Show("splash")
        }
        return this.launchOk
    }

    IsFocused() => this.focused

    Focus() => this.isRunning && this.IsFocused()

    WaitingForUser() => this.isRunning && !this.IsFocused() && this.userActive

    Unlocked() => !this.locked

    Close(linger := 0) {
        this.closes++
        this.lingered := linger
        this.isRunning := false
        this.screen.visible := Map()
    }
}

; Someone uses the PC (another window in front) until ``busyUntil``.
class BusyGame extends FakeGame {
    __New(screen, clock, busyUntil) {
        super.__New(screen)
        this.clock := clock
        this.busyUntil := busyUntil
        this.userActive := true
    }

    IsFocused() => this.clock.at >= this.busyUntil
}

; HLL Vietnam's join flow as seen on 2026-10-24 (v1.7). "splash" isn't a
; button the seeder looks for; it stands in for the press-any-button screen.
HappyPath() {
    units := ["switch_team", "faction_nva", "squad_join", "infantry_create"]
    return Map(
        "splash|space", [["splash"], ["menu_enlist"]],
        "menu_enlist", [["menu_enlist"], ["browser_search", "browser_refresh", "browser_join"]],
        "browser_search|enter", [["browser_search"], ["server_row"]],
        "browser_refresh|r", [[], []],
        "browser_join", [["server_row", "browser_join", "browser_refresh"], ["select_force", "force_us", "force_nva", "admin_yes"]],
        ; Units also lists open squads ("squad_join" stands for their join
        ; arrows); the seeder must never click one.
        "force_us", [["select_force", "force_us", "force_nva"], ["switch_team", "squad_join", "infantry_create"]],
        "force_nva", [["select_force", "force_us", "force_nva"], ["switch_team", "faction_nva", "squad_join", "infantry_create"]],
        "squad_join", [units, ["roles_confirm"]],
        "infantry_create", [units, ["create_unit", "create_unit_button"]],
        "create_unit_button", [["create_unit", "create_unit_button"], ["roles_confirm"]],
        "switch_team", [["faction_nva"], []],
        "admin_yes", [["admin_yes"], []],
        "admin_yes|y", [["admin_yes"], []],
        "roles_confirm|f", [["roles_confirm"], ["deploy_button"]],
        "deploy_button|f", [["deploy_button"], []],
        "game_menu_leave|esc", [["game_menu_leave"], []])
}

; The Units screen as the fake shows it.
UNITS := ["switch_team", "faction_nva", "squad_join", "infantry_create"]

FakeStatus(players, allied, axis, name := "Syndicate") => {name: name, players: players, allied: allied, axis: axis, timeRemaining: 3000}

; A fetch that returns each count in turn, then repeats the last. "" stands for
; the server being unreachable.
Statuses(counts, alliedHeavy := true) {
    queue := counts.Clone()
    fetch(url) {
        count := queue.Length > 1 ? queue.RemoveAt(1) : queue[1]
        if count = ""
            return ""
        big := count - count // 2, small := count // 2
        return alliedHeavy ? FakeStatus(count, big, small) : FakeStatus(count, small, big)
    }
    return fetch
}

; Seeds with the fakes; leaving waits half of leave_delay_minutes unless ``rng`` says otherwise.
SeedWith(config, game, screen, fetch, clock, rng := "") => Runner.Seed(config, game, screen, fetch, clock, rng ? rng : () => 0.5)

; Swaps methods and properties for a test; the test runner undoes them after each test.
class Patches {
    static saved := []

    static Set(obj, name, fn) {
        Patches.saved.Push([obj, name, obj.HasOwnProp(name) ? obj.GetOwnPropDesc(name) : ""])
        obj.DefineProp(name, {Call: fn})
    }

    static Value(obj, name, value) {
        Patches.saved.Push([obj, name, obj.HasOwnProp(name) ? obj.GetOwnPropDesc(name) : ""])
        obj.DefineProp(name, {Value: value})
    }

    static Undo() {
        while Patches.saved.Length {
            item := Patches.saved.Pop()
            if IsObject(item[3])
                item[1].DefineProp(item[2], item[3])
            else
                item[1].DeleteProp(item[2])
        }
    }
}

; Assertions

Assert(condition, message := "assertion failed") {
    if !condition
        throw Error(message, -1)
}

AssertEq(got, want, message := "") {
    if !Same(got, want)
        throw Error((message != "" ? message ": " : "") "got " Show(got) ", expected " Show(want), -1)
}

; Calls ``fn`` and checks that it throws a ``kind`` (an error class). Returns the error.
AssertThrows(kind, fn, message := "") {
    try {
        fn()
    } catch as err {
        if err is kind
            return err
        throw Error((message != "" ? message ": " : "") "threw " Type(err) " (" err.Message "), expected "
            . kind.Prototype.__Class, -1)
    }
    throw Error((message != "" ? message ": " : "") "didn't throw " kind.Prototype.__Class, -1)
}

Fail(message) {
    throw Error(message, -1)
}

; Deep equality for strings, numbers, Arrays and Maps; strings compare case-sensitively.
Same(a, b) {
    if a is Array {
        if !(b is Array) || a.Length != b.Length
            return false
        loop a.Length
            if !Same(a[A_Index], b[A_Index])
                return false
        return true
    }
    if a is Map {
        if !(b is Map) || a.Count != b.Count
            return false
        for key, value in a
            if !b.Has(key) || !Same(value, b[key])
                return false
        return true
    }
    if IsObject(a) || IsObject(b)
        return a == b
    if IsNumber(a) && IsNumber(b) && !(a is String && b is String)
        return a = b
    return a == b
}

Show(value) {
    if value is Array {
        out := ""
        for item in value
            out .= (A_Index > 1 ? ", " : "") Show(item)
        return "[" out "]"
    }
    if value is Map {
        out := ""
        for key, item in value
            out .= (A_Index > 1 ? ", " : "") Show(key) ": " Show(item)
        return "{" out "}"
    }
    if IsObject(value)
        return Type(value)
    return value is String ? '"' value '"' : String(value)
}

Count(list, value) {
    n := 0
    for item in list
        if item == value
            n++
    return n
}

IndexOf(list, value) {
    for item in list
        if item == value
            return A_Index
    return 0
}

Includes(list, value) => IndexOf(list, value) > 0

; Items of ``list`` equal to ``value``.
Only(list, value) {
    out := []
    for item in list
        if item == value
            out.Push(item)
    return out
}

Slice(list, start, stop := "") {
    out := []
    stop := stop = "" ? list.Length : Min(stop, list.Length)
    loop stop - start + 1
        out.Push(list[start + A_Index - 1])
    return out
}

; A stand-in WinHTTP request whose ResponseBody, like the real one, is a new
; byte array on every read. ``ready`` false: one that never gets its answer.
class FakeResponse {
    __New(text, ready := true) {
        this.bytes := Buffer(Max(0, StrPut(text, "UTF-8") - 1))
        if this.bytes.Size
            StrPut(text, this.bytes, "UTF-8")
        this.ready := ready, this.aborted := false
    }
    WaitForResponse(timeout := -1) => this.ready
    Abort() => this.aborted := true
    Status => 200
    ResponseBody {
        get {
            body := ComObjArray(0x11, this.bytes.Size)  ; VT_UI1
            if this.bytes.Size
                DllCall("RtlMoveMemory", "Ptr", NumGet(ComObjValue(body), 8 + A_PtrSize, "Ptr"), "Ptr", this.bytes, "UPtr", this.bytes.Size)
            return body
        }
    }
}
