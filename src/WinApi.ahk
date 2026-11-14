; The Windows calls the seeder needs for windows, focus and input.
;
; Keys go out through SendInput with scancodes looked up for the game's
; keyboard layout, so QWERTZ/AZERTY players get the right letters, and text
; is typed as Unicode characters. Nothing here installs a keyboard or mouse hook.

class WinApi {
    static VK := Map("space", 0x20, "enter", 0x0D, "esc", 0x1B, "backspace", 0x08, "alt", 0x12)
    static INPUT_SIZE := 8 + 32  ; INPUT on 64-bit Windows: type, then the union (MOUSEINPUT is the largest)

    ; Windows counts the seeder's own input as activity too. So before sending
    ; any, note whether the latest input was the player's; UserIdleSeconds then
    ; uses that instead of ours. Ticks are GetTickCount() values.
    static ownInputTick := ""
    static playerInputTick := ""
    static OWN_INPUT_SLACK_MS := 250  ; how long after we send input Windows may stamp it
    ; Other programs can send input that does nothing, too: games built on
    ; Unreal Engine, Hell Let Loose: Vietnam among them, send a mouse signal
    ; that doesn't move the pointer every 50 s, to keep the screensaver off.
    ; Windows counts it as input, so the PC would never look idle while the
    ; game is open. While WatchInput is on, this is the time Windows gave the
    ; latest such signal, which UserIdleSeconds then skips.
    static emptyInputTick := ""
    static watcher := ""  ; WatchInput's message handler and timer, while on
    ; The window our input is for (the game, set by Focus). Input is dropped
    ; if another window has come to the front since, e.g. the player clicked
    ; back into their browser halfway through typing the server name.
    static inputTarget := 0

    ; Coordinates in real screen pixels on every monitor, whatever its scaling.
    static MakeDpiAware() {
        try {
            if DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")  ; per monitor v2
                return
        }
        try DllCall("SetThreadDpiAwarenessContext", "Ptr", -3, "Ptr")  ; per monitor
    }

    static _Ours(lastInput, ownInput) => ownInput != "" && ((lastInput - ownInput) & 0xFFFFFFFF) <= WinApi.OWN_INPUT_SLACK_MS

    static _LastInput() {
        info := Buffer(8, 0)
        NumPut("UInt", 8, info)
        return DllCall("GetLastInputInfo", "Ptr", info) ? NumGet(info, 4, "UInt") : ""
    }

    ; ``switched``: the game lost the front since the key or button went down,
    ; so someone switched away and the latest input is theirs, even if it came
    ; within OWN_INPUT_SLACK_MS of ours (an Alt+Tab during a strafe). If a
    ; popup took the front instead, this counts ours as theirs, which only
    ; makes the PC look busy for longer.
    static _MarkOwnInput(switched := false) {
        last := WinApi._LastInput()
        if last != "" && last != WinApi.emptyInputTick && (switched || !WinApi._Ours(last, WinApi.ownInputTick))
            WinApi.playerInputTick := last
        WinApi.ownInputTick := DllCall("GetTickCount", "UInt")
    }

    ; Notes the latest input as the player's, unless it was ours or an empty signal.
    static _NoteInput() {
        last := WinApi._LastInput()
        if last != "" && last != WinApi.emptyInputTick && !WinApi._Ours(last, WinApi.ownInputTick)
            WinApi.playerInputTick := last
    }

    ; Turns on or off watching for programs' empty mouse signals, used while
    ; the seeder waits for the PC to be left alone. It asks Windows for raw
    ; input from the mouse only, never the keyboard, and of each mouse event
    ; looks only at whether a program sent it and whether it did anything;
    ; it keeps nothing but the time of the latest empty one. While on, it
    ; also notes the latest input every second, so a signal can't hide the
    ; player's typing from just before it.
    static WatchInput(on) {
        if !on = !WinApi.watcher
            return
        rid := Buffer(8 + A_PtrSize, 0)  ; RAWINPUTDEVICE: the mouse, sent to our hidden window even when it isn't in front
        NumPut("UShort", 1, "UShort", 2, "UInt", on ? 0x100 : 0x1, "Ptr", on ? A_ScriptHwnd : 0, rid)  ; RIDEV_INPUTSINK, RIDEV_REMOVE
        if on {
            if !DllCall("RegisterRawInputDevices", "Ptr", rid, "UInt", 1, "UInt", rid.Size)
                return  ; empty signals count as input then, as they did before
            WinApi.watcher := {input: ObjBindMethod(WinApi, "_OnRawInput"), note: ObjBindMethod(WinApi, "_NoteInput")}
            OnMessage(0xFF, WinApi.watcher.input)  ; WM_INPUT
            SetTimer(WinApi.watcher.note, 1000)
        } else {
            DllCall("RegisterRawInputDevices", "Ptr", rid, "UInt", 1, "UInt", rid.Size)
            OnMessage(0xFF, WinApi.watcher.input, 0)
            SetTimer(WinApi.watcher.note, 0)
            WinApi.watcher := ""
        }
    }

    static _OnRawInput(wParam, lParam, *) {
        header := 8 + 2 * A_PtrSize  ; RAWINPUTHEADER
        size := header + 24          ; then RAWMOUSE
        raw := Buffer(size, 0)
        if DllCall("GetRawInputData", "Ptr", lParam, "UInt", 0x10000003, "Ptr", raw, "UInt*", &size, "UInt", header, "UInt") = 0xFFFFFFFF  ; RID_INPUT
            return
        if WinApi.EmptyMouse(raw)
            WinApi.emptyInputTick := WinApi._LastInput()
    }

    ; True if ``raw`` (a RAWINPUT) is a mouse event that a program sent, not
    ; a mouse or touchpad, and that moves, presses, releases and scrolls nothing.
    static EmptyMouse(raw) {
        mouse := 8 + 2 * A_PtrSize  ; RAWMOUSE, after the header
        return NumGet(raw, 0, "UInt") = 0        ; RIM_TYPEMOUSE
            && !NumGet(raw, 8, "Ptr")            ; no device
            && !(NumGet(raw, mouse, "UShort") & 1)  ; a relative move, not to a point on the screen
            && !NumGet(raw, mouse + 4, "UShort")    ; no button or wheel
            && !NumGet(raw, mouse + 12, "Int") && !NumGet(raw, mouse + 16, "Int")  ; no movement
    }

    static SetInputTarget(hwnd) => WinApi.inputTarget := hwnd

    static _OnTarget() => !WinApi.inputTarget || DllCall("GetForegroundWindow", "Ptr") = WinApi.inputTarget

    ; Sends INPUT structs. ``always`` sends even when the game isn't in front:
    ; "release" for releasing keys and buttons (harmless in any window, and
    ; they mustn't stay held down), true for ForceToFront's nudges.
    static _Send(inputs, always := false) {
        onTarget := WinApi._OnTarget()
        if !always && !onTarget
            return
        WinApi._MarkOwnInput(always = "release" && !onTarget)
        size := WinApi.INPUT_SIZE
        data := Buffer(size * inputs.Length, 0)
        for item in inputs {
            base := (A_Index - 1) * size
            NumPut("UInt", item.type, data, base)
            if item.type = 1 {  ; keyboard
                NumPut("UShort", item.vk, data, base + 8)
                NumPut("UShort", item.scan, data, base + 10)
                NumPut("UInt", item.flags, data, base + 12)
            } else {  ; mouse: no movement, just the flags
                NumPut("UInt", item.flags, data, base + 20)
            }
        }
        DllCall("SendInput", "UInt", inputs.Length, "Ptr", data, "Int", size, "UInt")
    }

    static _Key(scan := 0, vk := 0, flags := 0) => {type: 1, scan: scan, vk: vk, flags: flags}
    static _Mouse(flags) => {type: 0, flags: flags}

    ; Windows

    static WindowPid(hwnd) {
        DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "UInt*", &pid := 0)
        return pid
    }

    ; The process's largest visible top-level window that no other window owns, or 0.
    static MainWindow(pid) {
        best := 0, bestArea := -1
        for hwnd in WinGetList("ahk_pid " pid) {
            if !DllCall("IsWindowVisible", "Ptr", hwnd) || DllCall("GetWindow", "Ptr", hwnd, "UInt", 4, "Ptr")
                continue
            rect := Buffer(16, 0)
            DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", rect)
            area := (NumGet(rect, 8, "Int") - NumGet(rect, 0, "Int")) * (NumGet(rect, 12, "Int") - NumGet(rect, 4, "Int"))
            if area > bestArea || (area = bestArea && hwnd > best)
                best := hwnd, bestArea := area
        }
        return best
    }

    ; [left, top, width, height] of the window's client area on the virtual desktop, or "".
    static ClientRect(hwnd) {
        rect := Buffer(16, 0)
        if !DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rect)
            return ""
        w := NumGet(rect, 8, "Int"), h := NumGet(rect, 12, "Int")
        if w <= 0 || h <= 0
            return ""
        origin := Buffer(8, 0)
        DllCall("ClientToScreen", "Ptr", hwnd, "Ptr", origin)
        return [NumGet(origin, 0, "Int"), NumGet(origin, 4, "Int"), w, h]
    }

    static InFront(hwnd) => DllCall("GetForegroundWindow", "Ptr") = hwnd

    static IsMinimised(hwnd) => DllCall("IsIconic", "Ptr", hwnd)

    ; The window in front, or 0 when there's none.
    static ForegroundWindow() => DllCall("GetForegroundWindow", "Ptr")

    ; The name of the program running as ``pid``, or "" if it has gone.
    static ProcessName(pid) {
        try
            return ProcessGetName(pid)
        catch
            return ""
    }

    static OwnPid() => DllCall("GetCurrentProcessId", "UInt")

    static ForegroundPid() {
        hwnd := DllCall("GetForegroundWindow", "Ptr")
        return hwnd ? WinApi.WindowPid(hwnd) : 0
    }

    ; Asks Windows to make hwnd the foreground window. True once it is, and
    ; isn't minimised. Windows usually refuses while someone is using another
    ; window, but not always (after its foreground lock timeout, for one), so
    ; HllGame.Focus only asks while no other program's window is in front;
    ; ForceToFront is for when the PC has been left alone.
    static BringToFront(hwnd) {
        if DllCall("GetForegroundWindow", "Ptr") != hwnd {
            DllCall("SetForegroundWindow", "Ptr", hwnd)
            if DllCall("GetForegroundWindow", "Ptr") != hwnd
                return false
        }
        if DllCall("IsIconic", "Ptr", hwnd) {
            DllCall("ShowWindowAsync", "Ptr", hwnd, "Int", 9)  ; SW_RESTORE; async, so a frozen game can't block us
            return false  ; ready on the next try
        }
        return true
    }

    ; Makes hwnd the foreground window even though another program has it.
    ; Only for when nobody is using the PC. True if it worked.
    ;
    ; Windows lets the program that sent the latest input change the
    ; foreground window, so this first sends a mouse move of zero pixels:
    ; input that no window reacts to. That also works when the foreground is
    ; an invisible window, like the "Windows Input Experience" that took over
    ; in a live test (2026-10-26). An Alt tap is the fallback.
    static ForceToFront(hwnd, altTap := true) {
        if DllCall("IsHungAppWindow", "Ptr", hwnd)
            return false  ; not answering messages; activating it could block us
        if DllCall("IsIconic", "Ptr", hwnd)
            DllCall("ShowWindowAsync", "Ptr", hwnd, "Int", 9)
        if WinApi.BringToFront(hwnd)
            return true
        WinApi._Send([WinApi._Mouse(0x1)], true)  ; MOUSEEVENTF_MOVE by nothing
        if WinApi._AskForFront(hwnd)
            return true
        if altTap && DllCall("GetForegroundWindow", "Ptr") != hwnd {  ; if it's ours, it's only still restoring
            ; Nobody is typing, so the Alt can't land in their work.
            WinApi._Send([WinApi._Key(0, WinApi.VK["alt"]), WinApi._Key(0, WinApi.VK["alt"], 0x2)], true)
            return WinApi._AskForFront(hwnd)
        }
        return false
    }

    ; SetForegroundWindow, retried briefly: SendInput only queues the input,
    ; and the right to change the foreground comes once Windows handles it.
    static _AskForFront(hwnd, tries := 5) {
        loop tries {
            Sleep(50)
            if DllCall("GetForegroundWindow", "Ptr") != hwnd
                DllCall("SetForegroundWindow", "Ptr", hwnd)
            if DllCall("GetForegroundWindow", "Ptr") = hwnd && !DllCall("IsIconic", "Ptr", hwnd)  ; restored, not just in front
                return true
        }
        return false
    }

    ; Seconds since the player last used the mouse or keyboard; the seeder's
    ; own input doesn't count, nor, while WatchInput is on, a program's empty
    ; mouse signals.
    static UserIdleSeconds() {
        WinApi._NoteInput()
        last := WinApi._LastInput()
        if last = ""
            return 0.0
        return WinApi.IdleMs(DllCall("GetTickCount", "UInt"), last, WinApi.ownInputTick, WinApi.playerInputTick,
            WinApi.emptyInputTick) / 1000
    }

    ; Milliseconds of player inactivity from GetTickCount() values, which wrap
    ; around every 49.7 days.
    static IdleMs(now, lastInput, ownInput, playerInput, emptyInput := "") {
        if WinApi._Ours(lastInput, ownInput)  ; the latest input was ours; the player's came before it
            lastInput := playerInput != "" ? playerInput : ownInput
        else if lastInput = emptyInput && playerInput != ""  ; a program's empty signal
            lastInput := playerInput
        idle := (now - lastInput) & 0xFFFFFFFF
        ; Another program's SendInput can stamp input with its own time, even
        ; one a little ahead of now: that's input just now, not 49 days ago.
        return idle >= 0x80000000 ? 0 : idle
    }

    ; Flashes the window's taskbar button until it comes to the front.
    static Flash(hwnd) {
        info := Buffer(32, 0)  ; FLASHWINFO
        NumPut("UInt", 32, info, 0), NumPut("Ptr", hwnd, info, 8)
        NumPut("UInt", 0x2 | 0xC, info, 16)  ; FLASHW_TRAY | FLASHW_TIMERNOFG
        DllCall("FlashWindowEx", "Ptr", info)
    }

    ; False while the PC is locked (input can't reach a locked desktop).
    static DesktopUnlocked() {
        desktop := DllCall("OpenInputDesktop", "UInt", 0, "Int", false, "UInt", 0x0100, "Ptr")  ; DESKTOP_SWITCHDESKTOP
        if !desktop
            return false
        DllCall("CloseDesktop", "Ptr", desktop)
        return true
    }

    ; Input

    static ClickAt(x, y) {
        if !WinApi._OnTarget()
            return  ; leave the player's cursor alone
        DllCall("SetCursorPos", "Int", x, "Int", y)
        Sleep(100)
        WinApi._Send([WinApi._Mouse(0x2)])  ; left down
        Sleep(50)
        WinApi._Send([WinApi._Mouse(0x4)], "release")  ; left up
    }

    static MoveCursor(x, y) {
        if WinApi._OnTarget()
            DllCall("SetCursorPos", "Int", x, "Int", y)
    }

    ; Scancode of the key that produces ``key`` on the foreground window's layout.
    static _Scancode(key) {
        if WinApi.VK.Has(key)
            return DllCall("MapVirtualKeyExW", "UInt", WinApi.VK[key], "UInt", 0, "Ptr", 0, "UInt")
        thread := DllCall("GetWindowThreadProcessId", "Ptr", DllCall("GetForegroundWindow", "Ptr"), "Ptr", 0, "UInt")
        layout := DllCall("GetKeyboardLayout", "UInt", thread, "Ptr")
        vk := WinApi.KeyFor(key, WinApi.VkScan(key, layout))
        return DllCall("MapVirtualKeyExW", "UInt", vk, "UInt", 0, "Ptr", layout, "UInt")  ; MAPVK_VK_TO_VSC
    }

    ; The key (and Shift state) that types ``key`` on keyboard ``layout``, or
    ; -1 if none does (WinApi's, so tests can swap it).
    static VkScan(key, layout) => DllCall("VkKeyScanExW", "UShort", Ord(key), "Ptr", layout, "Short")

    ; The virtual key to press for ``key``, given what VkKeyScanExW says types
    ; it on the game's layout. When no key types a letter on its own (-1 on
    ; Russian, Greek and other non-Latin layouts, or only with Shift or AltGr),
    ; the letter's own key: A to Z keep their places on every layout.
    static KeyFor(key, scan) {
        if (scan = -1 || scan & 0xFF00) && key ~= "^[a-z]$"
            return Ord(StrUpper(key))
        return scan & 0xFF
    }

    static KeyDown(key) => WinApi._Send([WinApi._Key(WinApi._Scancode(key), 0, 0x8)])  ; KEYEVENTF_SCANCODE
    static KeyUp(key) => WinApi._Send([WinApi._Key(WinApi._Scancode(key), 0, 0x8 | 0x2)], "release")

    static Press(key) {
        WinApi.KeyDown(key)
        Sleep(50)
        WinApi.KeyUp(key)
    }

    static TypeText(text) {
        loop parse text {
            code := Ord(A_LoopField)
            WinApi._Send([WinApi._Key(code, 0, 0x4), WinApi._Key(code, 0, 0x4 | 0x2)])  ; KEYEVENTF_UNICODE
            Sleep(40)
        }
    }

    ; Stop key

    ; Calls ``onPress`` when Ctrl+Alt+End is pressed anywhere. Uses
    ; RegisterHotKey, so it never needs a keyboard hook. False if another
    ; program already has that key.
    static ListenForStopKey(onPress) {
        handler(wParam, lParam, msg, hwnd) {
            if wParam = 1
                onPress()
            return 0
        }
        if !DllCall("RegisterHotKey", "Ptr", A_ScriptHwnd, "Int", 1, "UInt", 0x2 | 0x1 | 0x4000, "UInt", 0x23)  ; Ctrl+Alt, no repeat, End
            return false
        OnMessage(0x0312, handler)  ; WM_HOTKEY
        return true
    }
}
