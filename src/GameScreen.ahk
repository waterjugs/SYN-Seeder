; The real screen and input: captures where the game is drawn, finds buttons
; on it with Vision, and clicks and types into the game. The tests use a fake
; with the same methods (tests/Fakes.ahk).

class GameScreen {
    static BLACK_WARNING_TICKS := 10  ; black captures in a row before the log says why

    ; ``crops`` are the button images (Buttons.Load). ``rect`` is called on every
    ; refresh and returns where the game is drawn, [left, top, width, height],
    ; or "" to use the primary monitor; so resolution changes and other
    ; monitors are followed.
    __New(crops, rect := "") {
        WinApi.MakeDpiAware()
        this.vision := Vision(crops)
        this.rect := rect
        this.area := GameScreen.Primary()
        this.blackTicks := 0
        this.dib := ""  ; the working-size capture, kept between refreshes
    }

    __Delete() => this._FreeDib()

    ; The primary monitor: {left, top, w, h}.
    static Primary() => {left: 0, top: 0, w: A_ScreenWidth, h: A_ScreenHeight}

    ; Takes a new screenshot; Find and FindAll use it until the next refresh.
    Refresh() {
        rect := this.rect ? (this.rect)() : ""
        this.area := rect ? {left: rect[1], top: rect[2], w: rect[3], h: rect[4]} : GameScreen.Primary()
        area := this.area
        f := Vision.Factor(area.h)
        w := Max(1, area.w // f), h := Max(1, area.h // f)
        frame := this._Grab(w, h, f)
        this.blackTicks := GameScreen.LooksBlack(frame.bits, w, h) ? this.blackTicks + 1 : 0
        if this.blackTicks = GameScreen.BLACK_WARNING_TICKS
            Logs.Warning("Screen captures are coming back black. Set the game's display mode to "
                . "Borderless / Windowed Fullscreen.")
        this.vision.SetFrame(frame.bits, w, h, w * 4, area.w, area.h, f, area.left, area.top)
    }

    ; Centre of ``name`` on screen as [x, y], or "" when it isn't showing.
    Find(name, region := "") {
        if !this.vision.ready
            this.Refresh()
        return this.vision.Find(name, region)
    }

    FindAll(name, region := "") {
        if !this.vision.ready
            this.Refresh()
        return this.vision.FindAll(name, region)
    }

    ; Acting

    Click(pos) {
        if !pos  ; the button went away since the screen was read
            return
        WinApi.ClickAt(pos[1], pos[2])
        Sleep(100)
        ; Park the cursor at the edge so hover highlights don't change the next match.
        WinApi.MoveCursor(this.area.left + 5, this.area.top + this.area.h // 2)
    }

    TypeText(text) => WinApi.TypeText(text)

    Press(key) => WinApi.Press(key)

    Hold(key, seconds) {
        WinApi.KeyDown(key)
        try
            Sleep(Round(seconds * 1000))
        finally
            WinApi.KeyUp(key)
    }

    ; Saves the area of the last refresh at full size as a PNG, without
    ; replacing the frame being matched.
    SaveScreenshot(path) {
        area := this.area
        shot := GameScreen._MakeDib(area.w, area.h)
        try {
            GameScreen._Copy(shot.dc, area.w, area.h, area, 1)
            Gdip.SavePng(shot.hbm, path)
        } finally {
            GameScreen._FreeDibOf(shot)
        }
    }

    ; True if a frame (32-bit pixels) is black or nearly: every sampled
    ; pixel's red, green and blue are under 16. That's what a capture of a
    ; game in exclusive fullscreen gives.
    static LooksBlack(bits, w, h) {
        total := w * h
        step := Max(1, total // 40000) | 1  ; odd, so the samples walk across columns too
        i := 0
        while i < total {
            if NumGet(bits, i * 4, "UInt") & 0xF0F0F0
                return false
            i += step
        }
        return true
    }

    ; The capture at working size: the game's area shrunk by f, each pixel the
    ; average of an f x f block (StretchBlt in HALFTONE mode).
    _Grab(w, h, f) {
        if !this.dib || this.dib.w != w || this.dib.h != h {
            this._FreeDib()
            this.dib := GameScreen._MakeDib(w, h)
        }
        GameScreen._Copy(this.dib.dc, w, h, this.area, f)
        return this.dib
    }

    ; Copies the screen at ``area`` into a memory DC, shrinking by ``f``.
    static _Copy(dc, w, h, area, f) {
        screen := DllCall("GetDC", "Ptr", 0, "Ptr")
        if !screen
            throw OSError("Couldn't read the screen")
        rop := 0x00CC0020 | 0x40000000  ; SRCCOPY | CAPTUREBLT (include layered windows)
        try {
            if f = 1 {
                ok := DllCall("gdi32\BitBlt", "Ptr", dc, "Int", 0, "Int", 0, "Int", w, "Int", h,
                    "Ptr", screen, "Int", area.left, "Int", area.top, "UInt", rop)
            } else {
                DllCall("gdi32\SetStretchBltMode", "Ptr", dc, "Int", 4)  ; HALFTONE: averages the block
                DllCall("gdi32\SetBrushOrgEx", "Ptr", dc, "Int", 0, "Int", 0, "Ptr", 0)
                ok := DllCall("gdi32\StretchBlt", "Ptr", dc, "Int", 0, "Int", 0, "Int", w, "Int", h,
                    "Ptr", screen, "Int", area.left, "Int", area.top, "Int", w * f, "Int", h * f, "UInt", rop)
            }
        } finally {
            DllCall("ReleaseDC", "Ptr", 0, "Ptr", screen)
        }
        if !ok
            throw OSError("Couldn't capture the screen")
        DllCall("gdi32\GdiFlush")
    }

    ; A top-down 32-bit bitmap selected into its own memory DC: {w, h, dc, hbm, old, bits}.
    static _MakeDib(w, h) {
        info := Buffer(40, 0)  ; BITMAPINFOHEADER
        NumPut("UInt", 40, info, 0), NumPut("Int", w, info, 4), NumPut("Int", -h, info, 8)
        NumPut("UShort", 1, info, 12), NumPut("UShort", 32, info, 14)
        hbm := DllCall("gdi32\CreateDIBSection", "Ptr", 0, "Ptr", info, "UInt", 0, "Ptr*", &bits := 0, "Ptr", 0, "UInt", 0, "Ptr")
        if !hbm || !bits
            throw OSError("Couldn't make a " w "x" h " bitmap for the screen")
        dc := DllCall("gdi32\CreateCompatibleDC", "Ptr", 0, "Ptr")
        if !dc {
            DllCall("gdi32\DeleteObject", "Ptr", hbm)
            throw OSError("Couldn't make a drawing surface for the screen")
        }
        old := DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", hbm, "Ptr")
        return {w: w, h: h, dc: dc, hbm: hbm, old: old, bits: bits}
    }

    static _FreeDibOf(dib) {
        DllCall("gdi32\SelectObject", "Ptr", dib.dc, "Ptr", dib.old)
        DllCall("gdi32\DeleteDC", "Ptr", dib.dc)
        DllCall("gdi32\DeleteObject", "Ptr", dib.hbm)
    }

    _FreeDib() {
        if this.dib
            GameScreen._FreeDibOf(this.dib)
        this.dib := ""
    }
}
