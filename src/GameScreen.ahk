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
        this.dib := ""   ; the working-size capture, kept between refreshes
        this.full := ""  ; the full-size capture it's shrunk from, likewise
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
            GameScreen._Copy(shot.dc, area.w, area.h, area)
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
    ; average of an f x f block (see Shrink).
    _Grab(w, h, f) {
        if !this.dib || this.dib.w != w || this.dib.h != h {
            if this.dib
                GameScreen._FreeDibOf(this.dib)
            this.dib := ""
            this.dib := GameScreen._MakeDib(w, h)
        }
        if f = 1 {
            GameScreen._Copy(this.dib.dc, w, h, this.area)
            return this.dib
        }
        if !this.full || this.full.w != w * f || this.full.h != h * f {
            if this.full
                GameScreen._FreeDibOf(this.full)
            this.full := ""
            this.full := GameScreen._MakeDib(w * f, h * f)
        }
        GameScreen._Copy(this.full.dc, w * f, h * f, this.area)
        GameScreen.Shrink(this.full, this.dib, f)
        return this.dib
    }

    ; Copies the screen at ``area`` into a memory DC, at full size.
    static _Copy(dc, w, h, area) {
        screen := DllCall("GetDC", "Ptr", 0, "Ptr")
        if !screen
            throw OSError("Couldn't read the screen")
        rop := 0x00CC0020 | 0x40000000  ; SRCCOPY | CAPTUREBLT (include layered windows)
        try {
            ok := DllCall("gdi32\BitBlt", "Ptr", dc, "Int", 0, "Int", 0, "Int", w, "Int", h,
                "Ptr", screen, "Int", area.left, "Int", area.top, "UInt", rop)
        } finally {
            DllCall("ReleaseDC", "Ptr", 0, "Ptr", screen)
        }
        if !ok
            throw OSError("Couldn't capture the screen")
        DllCall("gdi32\GdiFlush")
    }

    static shrinkWarned := false

    ; Shrinks the bitmap ``src`` into ``dst``, which is ``f`` times smaller each
    ; way, making each pixel the average of an f x f block, as the screenshot
    ; cases the button finder is tested on are made. Windows Imaging
    ; Component's Fant scaler does that. If it can't, GDI's HALFTONE stretch
    ; does a rougher job (on Windows its pixels stray from the block averages
    ; by up to about 60 levels). Returns which of the two did it.
    static Shrink(src, dst, f) {
        try {
            Wic.Shrink(src.bits, dst.w * f, dst.h * f, src.w * 4, dst.bits, dst.w, dst.h)
            return "Windows Imaging Component"
        } catch as err {
            if !GameScreen.shrinkWarned {
                GameScreen.shrinkWarned := true
                Logs.Warning("Couldn't shrink the screen with Windows Imaging Component (" err.Message
                    . "), so buttons may be found less reliably.")
            }
        }
        DllCall("gdi32\SetStretchBltMode", "Ptr", dst.dc, "Int", 4)  ; HALFTONE
        DllCall("gdi32\SetBrushOrgEx", "Ptr", dst.dc, "Int", 0, "Int", 0, "Ptr", 0)
        DllCall("gdi32\StretchBlt", "Ptr", dst.dc, "Int", 0, "Int", 0, "Int", dst.w, "Int", dst.h,
            "Ptr", src.dc, "Int", 0, "Int", 0, "Int", dst.w * f, "Int", dst.h * f, "UInt", 0x00CC0020)
        DllCall("gdi32\GdiFlush")
        return "GDI"
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
        if this.full
            GameScreen._FreeDibOf(this.full)
        this.dib := "", this.full := ""
    }
}

; Windows Imaging Component, which shrinks screen captures for GameScreen.
class Wic {
    static factory := ""
    static format := ""

    ; Shrinks the top-down 32-bit pixels at ``src`` (``sw`` x ``sh``, ``stride``
    ; bytes a row) to ``dw`` x ``dh`` at ``dst`` with the Fant scaler, which
    ; averages the pixels each new pixel covers.
    static Shrink(src, sw, sh, stride, dst, dw, dh) {
        if !Wic.factory {
            ; CLSID_WICImagingFactory, IID_IWICImagingFactory
            Wic.factory := ComObject("{CACAF262-9370-4615-A13B-9F5539DA4C0A}", "{EC5EC8A9-C395-4314-9C77-54D7A935FF70}")
            Wic.format := Buffer(16)  ; GUID_WICPixelFormat32bppBGR
            DllCall("ole32\CLSIDFromString", "WStr", "{6FDDC324-4E03-4BFE-B185-3D77768DC90E}", "Ptr", Wic.format, "HRESULT")
        }
        bitmap := 0, scaler := 0
        try {
            ; IWICImagingFactory::CreateBitmapFromMemory (copies the pixels)
            ComCall(20, Wic.factory, "UInt", sw, "UInt", sh, "Ptr", Wic.format, "UInt", stride,
                "UInt", stride * sh, "Ptr", src, "Ptr*", &bitmap)
            ComCall(11, Wic.factory, "Ptr*", &scaler)  ; IWICImagingFactory::CreateBitmapScaler
            ComCall(8, scaler, "Ptr", bitmap, "UInt", dw, "UInt", dh, "Int", 3)  ; IWICBitmapScaler::Initialize, Fant
            ComCall(7, scaler, "Ptr", 0, "UInt", dw * 4, "UInt", dw * 4 * dh, "Ptr", dst)  ; IWICBitmapSource::CopyPixels
        } finally {
            if scaler
                ObjRelease(scaler)
            if bitmap
                ObjRelease(bitmap)
        }
    }
}
