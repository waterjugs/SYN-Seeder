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

    static _MarkOwnInput() {
        last := WinApi._LastInput()
        if last != "" && !WinApi._Ours(last, WinApi.ownInputTick)
            WinApi.playerInputTick := last
        WinApi.ownInputTick := DllCall("GetTickCount", "UInt")
    }

    static SetInputTarget(hwnd) => WinApi.inputTarget := hwnd

    static _OnTarget() => !WinApi.inputTarget || DllCall("GetForegroundWindow", "Ptr") = WinApi.inputTarget

    ; Sends INPUT structs. ``always`` sends even when the game isn't in front:
    ; for releasing keys and buttons (harmless in any window, and they mustn't
    ; stay held down) and for ForceToFront's nudges.
    static _Send(inputs, always := false) {
        if !always && !WinApi._OnTarget()
            return
        WinApi._MarkOwnInput()
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

    static ForegroundPid() {
        hwnd := DllCall("GetForegroundWindow", "Ptr")
        return hwnd ? WinApi.WindowPid(hwnd) : 0
    }

    ; Asks Windows to make hwnd the foreground window. True once it is, and
    ; isn't minimised. Windows refuses while someone is using another window,
    ; which is what we want then (a minimised game stays minimised too);
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

    ; Seconds since the player last used the mouse or keyboard; the seeder's own input doesn't count.
    static UserIdleSeconds() {
        last := WinApi._LastInput()
        if last = ""
            return 0.0
        return WinApi.IdleMs(DllCall("GetTickCount", "UInt"), last, WinApi.ownInputTick, WinApi.playerInputTick) / 1000
    }

    ; Milliseconds of player inactivity from GetTickCount() values, which wrap
    ; around every 49.7 days.
    static IdleMs(now, lastInput, ownInput, playerInput) {
        if WinApi._Ours(lastInput, ownInput)  ; the latest input was ours; the player's came before it
            lastInput := playerInput != "" ? playerInput : ownInput
        return (now - lastInput) & 0xFFFFFFFF
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
        WinApi._Send([WinApi._Mouse(0x4)], true)  ; left up
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
        vk := WinApi.KeyFor(key, DllCall("VkKeyScanExW", "UShort", Ord(key), "Ptr", layout, "Short"))
        return DllCall("MapVirtualKeyExW", "UInt", vk, "UInt", 0, "Ptr", layout, "UInt")  ; MAPVK_VK_TO_VSC
    }

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
    static KeyUp(key) => WinApi._Send([WinApi._Key(WinApi._Scancode(key), 0, 0x8 | 0x2)], true)

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
