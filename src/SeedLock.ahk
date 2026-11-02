; Making sure only one seeding run happens at a time, and starting and stopping one.
;
; A run holds a named mutex while it seeds. It also names its (hidden) main
; window "SynSeeder: seeding", so the setup window can find it and ask it to
; stop with a window message: the run then stops as if Ctrl+Alt+End was
; pressed, closing the game on its way out.

class SeedLock {
    static MUTEX := "Local\SynSeederSeeding"
    static TITLE := "SynSeeder: seeding"
    static handle := 0

    ; True if this process may seed; false if another run already is. Holds
    ; the lock until Release() or the process ends.
    static Claim() {
        h := DllCall("CreateMutexW", "Ptr", 0, "Int", false, "Str", SeedLock.MUTEX, "Ptr")
        if !h
            return false  ; e.g. a run started as administrator has it
        if A_LastError = 183 {  ; ERROR_ALREADY_EXISTS
            DllCall("CloseHandle", "Ptr", h)
            return false
        }
        SeedLock.handle := h
        return true
    }

    ; Lets go of the lock, so another process can take over the run.
    static Release() {
        if SeedLock.handle
            DllCall("CloseHandle", "Ptr", SeedLock.handle)
        SeedLock.handle := 0
    }

    ; True if a process holds the lock. Meaningful only while this one doesn't.
    static HeldElsewhere() {
        h := DllCall("OpenMutexW", "UInt", 0x00100000, "Int", false, "Str", SeedLock.MUTEX, "Ptr")  ; SYNCHRONIZE
        if !h
            return A_LastError = 5  ; access denied: it exists, held by a run started as administrator
        DllCall("CloseHandle", "Ptr", h)
        return true
    }

    ; The message that asks a run to stop.
    static StopMessage => DllCall("RegisterWindowMessageW", "Str", "SynSeederStopSeeding", "UInt")

    ; Marks this process as a seeding run and calls ``onStop`` when asked to stop.
    static Announce(onStop) {
        DllCall("SetWindowTextW", "Ptr", A_ScriptHwnd, "Str", SeedLock.TITLE)
        OnMessage(SeedLock.StopMessage, (*) => (onStop(), 0))
    }

    ; Main windows of the seeding runs, other than this process's own.
    static Runs() {
        out := []
        prev := DetectHiddenWindows(true)
        try {
            for hwnd in WinGetList(SeedLock.TITLE " ahk_class AutoHotkey")
                if hwnd != A_ScriptHwnd && WinGetTitle(hwnd) == SeedLock.TITLE
                    out.Push(hwnd)
        } finally {
            DetectHiddenWindows(prev)
        }
        return out
    }

    ; True while a run is going: one holds the lock, or is starting up or
    ; handing over to a new version and has its window up.
    static Running() => SeedLock.HeldElsewhere() || SeedLock.Runs().Length > 0

    ; Whether a process is still running, and ending one (SeedLock's, so tests can swap them).
    static Alive(pid) => ProcessExist(pid) != 0
    static End(pid) => ProcessClose(pid)

    ; Starts a program that keeps running after this one exits. Returns its process ID.
    static Spawn(program, arguments) {
        Run(QuoteArg(program) (arguments != "" ? " " arguments : ""), , , &pid)
        return pid
    }
}
