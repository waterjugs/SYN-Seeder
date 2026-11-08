; How the setup window looks: its colours, its fonts, and the pictures in it.
;
; Everything is drawn while the window runs, with GDI and GDI+ (Windows' own
; drawing libraries), so no image files are built into SynSeeder.exe. The
; shapes and colours are the ones the first (Python) SynSeeder drew into image
; files for its window.

class Look {
    ; Night sky warming to dusk, carried down through the window, with amber for first light.
    static NIGHT := 0x0C1823        ; top of the header's sky; the title bar on Windows 11
    static TWILIGHT := 0x151A27     ; window body
    static SLATE := 0x1F2335        ; fields
    static EDGE := 0x363A52         ; hairlines
    static HAZE := 0xECE3D0         ; main text
    static MIST := 0x9C98B0         ; secondary text
    static FIRST_LIGHT := 0xF2A443  ; the action to take, and a server that still needs seeding
    static PADDY := 0x86C17A        ; a seeded server
    static FLARE := 0xF27A62        ; errors
    static INK := 0x1A140C          ; text on the amber button
    static TRACK := 0x272B3F        ; empty part of the player meter
    static LINK_HOVER := 0xF7C27A
    static FOCUS := 0xB88A4A        ; keyboard focus ring

    ; The header's sky from top to bottom, and the glow along its bottom edge.
    static DUSK := [[0.0, 0x0C1823], [0.45, 0x1A2233], [0.8, 0x352B3E], [1.0, 0x4B3546]]
    static EMBER := 0x9E5141
    static SPROUT_GREEN := 0x7FCB5A
    static SPROUT_VEIN := 0x4E9A3A

    ; Sizes at 100% scaling.
    static HEADER_W := 480
    static HEADER_H := 92
    static TITLE := "SYN Vietnam Seeder"
    static TITLE_SIZE := 36  ; pixels
    static TITLE_Y := 18     ; the title's ascender line
    static MARK_Y := 8       ; the seedling's 64-unit box: stem on the baseline
    static MARK_UNIT := 0.8
    static MARK_GAP := 14    ; from the seedling's right leaf to the title

    static scale := 1.0      ; screen pixels per pixel at 100%

    ; Pixels at the screen's scaling for ``n`` pixels at 100%.
    static Px(n) => Round(n * Look.scale)

    static Hex(rgb) => Format("{:06X}", rgb)
    static ColorRef(rgb) => (rgb >> 16 & 0xFF) | (rgb & 0xFF00) | (rgb & 0xFF) << 16
    static Argb(rgb, alpha := 255) => (alpha << 24) | rgb

    ; ``a`` and ``b`` mixed: ``t`` of ``b``.
    static Mix(a, b, t) {
        out := 0
        for shift in [16, 8, 0] {
            x := a >> shift & 0xFF, y := b >> shift & 0xFF
            out |= Min(255, Max(0, Round(x + (y - x) * t))) << shift
        }
        return out
    }

    ; The colour at ``t`` (0 to 1) along ``stops``, a list of [position, colour].
    static Along(stops, t) {
        if t <= stops[1][1]
            return stops[1][2]
        loop stops.Length - 1 {
            a := stops[A_Index], b := stops[A_Index + 1]
            if t <= b[1]
                return Look.Mix(a[2], b[2], (t - a[1]) / (b[1] - a[1]))
        }
        return stops[stops.Length][2]
    }

    static FONT_WAIT := 3          ; seconds the window waits for fonts it hasn't got yet
    static FONT_RETRY_HOURS := 6   ; after that failed, how long the window opens without trying again

    ; Where a built SynSeeder.exe keeps the fonts it downloads.
    static FontFolder => App.InstallDir "\fonts"

    ; Makes the fonts usable by this process only, without installing them. A
    ; built exe downloads them into %LOCALAPPDATA%\SynSeeder\fonts (see
    ; GetFonts); a script uses the repository's assets\fonts. Windows' own
    ; fonts stand in for any that can't be had.
    static LoadFonts() {
        if App.Built {
            folder := Look.FontFolder
            try
                Look.GetFonts(Look.FONT_WAIT, true)
            catch as err
                Logs.Warning("Couldn't get the fonts: " err.Message)
        } else {  ; SynSeeder.ahk, or a script in tests\
            folder := DirExist(A_ScriptDir "\assets\fonts") ? A_ScriptDir "\assets\fonts" : A_ScriptDir "\..\assets\fonts"
        }
        loaded := 0
        for fileName, sha in FontFiles.SHA256 {
            path := folder "\" fileName
            if FileExist(path) && (!App.Built || Sha256.File(path) = sha)
                loaded += DllCall("gdi32\AddFontResourceExW", "Str", path, "UInt", 0x10, "Ptr", 0) > 0  ; FR_PRIVATE
        }
        return loaded
    }

    ; Downloads the fonts the font folder lacks from GitHub, all at once,
    ; waiting ``wait`` seconds at most. The window waits FONT_WAIT seconds,
    ; and ``sparing`` it: once a try has failed, it opens without trying again
    ; for FONT_RETRY_HOURS, so a PC that can't reach GitHub isn't kept waiting
    ; on every open. A seeding run has time to wait longer, and always tries.
    static GetFonts(wait, sparing := false) {
        folder := Look.FontFolder, note := folder "\download-failed.txt"
        if sparing && Look._FailedLately(note)
            return
        missing := RepoFiles.FetchAtOnce(folder, FontFiles.SHA256, Build.COMMIT != "" ? Build.COMMIT : "main", "assets/fonts", "font", wait)
        if missing.Length {
            out := FileOpen(note, "w")
            out.Write(A_NowUTC)  ; when, in the file itself: Windows doesn't always update a file's time
            out.Close()
        } else if FileExist(note) {
            FileDelete(note)
        }
    }

    ; True if ``note`` says a try failed less than FONT_RETRY_HOURS ago.
    static _FailedLately(note) {
        try {
            hours := DateDiff(A_NowUTC, Trim(FileRead(note)), "Hours")
            return hours >= 0 && hours < Look.FONT_RETRY_HOURS  ; (a clock put back doesn't count)
        }
        return false  ; no note, or one that can't be read: try
    }

    ; The first of ``faces`` that Windows has, or the last one.
    static PickFace(faces*) {
        for face in faces
            if Font(face, 10).actualFace = face
                return face
        return faces[faces.Length]
    }

    ; The quadratic Bezier curve from ``p0`` to ``p2`` pulled towards ``p1``, as ``n`` + 1 points [x, y].
    static Bezier(p0, p1, p2, n := 24) {
        out := []
        loop n + 1 {
            u := (A_Index - 1) / n
            a := (1 - u) ** 2, b := 2 * (1 - u) * u, c := u * u
            out.Push([a * p0[1] + b * p1[1] + c * p2[1], a * p0[2] + b * p1[2] + c * p2[2]])
        }
        return out
    }

    ; P(X <= x) for a standard normal X: how a blurred edge fades.
    static NormalCdf(x) {
        z := Abs(x) / Sqrt(2)
        t := 1 / (1 + 0.3275911 * z)  ; Abramowitz and Stegun 7.1.26
        erf := 1 - ((((1.061405429 * t - 1.453152027) * t + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * Exp(-z * z)
        return 0.5 * (1 + (x < 0 ? -erf : erf))
    }
}

; A GDI font, ``size`` in points at the screen's DPI, as the window's own labels use it.
class Font {
    __New(face, size, weight := 400, underline := false, pixels := 0) {
        this.face := face, this.size := size, this.weight := weight, this.underline := underline
        height := pixels ? -pixels : -Round(size * A_ScreenDPI / 72)
        this.handle := DllCall("CreateFontW", "Int", height, "Int", 0, "Int", 0, "Int", 0, "Int", weight
            , "UInt", 0, "UInt", underline, "UInt", 0, "UInt", 1, "UInt", 0, "UInt", 0, "UInt", 0, "UInt", 0, "Str", face, "Ptr")
        dc := DllCall("CreateCompatibleDC", "Ptr", 0, "Ptr")
        old := DllCall("SelectObject", "Ptr", dc, "Ptr", this.handle, "Ptr")
        tm := Buffer(64, 0)  ; TEXTMETRICW
        DllCall("GetTextMetricsW", "Ptr", dc, "Ptr", tm)
        this.height := NumGet(tm, 0, "Int"), this.ascent := NumGet(tm, 4, "Int"), this.descent := NumGet(tm, 8, "Int")
        name := Buffer(128, 0)
        DllCall("GetTextFaceW", "Ptr", dc, "Int", 64, "Ptr", name)
        this.actualFace := StrGet(name)
        DllCall("SelectObject", "Ptr", dc, "Ptr", old)
        DllCall("DeleteDC", "Ptr", dc)
    }

    __Delete() {
        if this.handle
            DllCall("DeleteObject", "Ptr", this.handle)
    }

    ; Options for Gui.SetFont, in colour ``rgb``.
    Options(rgb) => "norm s" this.size " w" this.weight (this.underline ? " underline" : "") " c" Look.Hex(rgb)

    ; How wide ``text`` is, in pixels.
    Width(text) {
        if text = ""
            return 0
        dc := DllCall("CreateCompatibleDC", "Ptr", 0, "Ptr")
        old := DllCall("SelectObject", "Ptr", dc, "Ptr", this.handle, "Ptr")
        size := Buffer(8, 0)
        DllCall("GetTextExtentPoint32W", "Ptr", dc, "Str", text, "Int", StrLen(text), "Ptr", size)
        DllCall("SelectObject", "Ptr", dc, "Ptr", old)
        DllCall("DeleteDC", "Ptr", dc)
        return NumGet(size, 0, "Int")
    }

    ; How far the ink of ``text`` starts after, and ends before, its advance: [left, right].
    Bearings(text) {
        if text = ""
            return [0, 0]
        dc := DllCall("CreateCompatibleDC", "Ptr", 0, "Ptr")
        old := DllCall("SelectObject", "Ptr", dc, "Ptr", this.handle, "Ptr")
        abc := Buffer(12, 0)
        first := Ord(SubStr(text, 1, 1)), last := Ord(SubStr(text, -1))
        left := right := 0
        if DllCall("GetCharABCWidthsFloatW", "Ptr", dc, "UInt", first, "UInt", first, "Ptr", abc)
            left := NumGet(abc, 0, "Float")
        if DllCall("GetCharABCWidthsFloatW", "Ptr", dc, "UInt", last, "UInt", last, "Ptr", abc)
            right := NumGet(abc, 8, "Float")
        DllCall("SelectObject", "Ptr", dc, "Ptr", old)
        DllCall("DeleteDC", "Ptr", dc)
        return [left, right]
    }
}

; A picture in memory, drawn with GDI+ (smoothed shapes) and GDI (text, the
; way the window's own labels draw it), then copied onto the screen.
; Coordinates are pixel edges: a 1 x 1 square at (0, 0) covers one pixel.
class Canvas {
    __New(w, h, background := "") {
        this.w := Max(1, w), this.h := Max(1, h), this.g := 0
        bi := Buffer(40, 0)  ; BITMAPINFOHEADER: top-down, 32 bits a pixel
        NumPut("UInt", 40, bi, 0), NumPut("Int", this.w, bi, 4), NumPut("Int", -this.h, bi, 8)
        NumPut("UShort", 1, bi, 12), NumPut("UShort", 32, bi, 14)
        this.dc := DllCall("CreateCompatibleDC", "Ptr", 0, "Ptr")
        this.hbm := DllCall("CreateDIBSection", "Ptr", this.dc, "Ptr", bi, "UInt", 0, "Ptr*", &bits := 0, "Ptr", 0, "UInt", 0, "Ptr")
        if !this.hbm
            throw OSError("Couldn't make a picture in memory")
        this.bits := bits
        this.old := DllCall("SelectObject", "Ptr", this.dc, "Ptr", this.hbm, "Ptr")
        DllCall("SetBkMode", "Ptr", this.dc, "Int", 1)  ; TRANSPARENT
        if background != ""
            this.Rect(0, 0, this.w, this.h, background)
    }

    __Delete() {
        this.Flush()
        DllCall("SelectObject", "Ptr", this.dc, "Ptr", this.old)
        DllCall("DeleteObject", "Ptr", this.hbm)
        DllCall("DeleteDC", "Ptr", this.dc)
    }

    ; GDI+ on this picture, smoothed, made on first use.
    Graphics {
        get {
            if !this.g {
                Gdip.Start()
                Canvas.Checked(DllCall("gdiplus\GdipCreateFromHDC", "Ptr", this.dc, "Ptr*", &g := 0), "GdipCreateFromHDC")
                DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", g, "Int", 4)     ; anti-alias
                DllCall("gdiplus\GdipSetPixelOffsetMode", "Ptr", g, "Int", 4)   ; pixel edges on whole numbers
                this.g := g
            }
            return this.g
        }
    }

    ; Finishes GDI+ drawing, so GDI can draw on top.
    Flush() {
        if this.g {
            DllCall("gdiplus\GdipDeleteGraphics", "Ptr", this.g)
            this.g := 0
        }
    }

    ; Fills a rectangle exactly (whole pixels, no smoothing).
    Rect(x, y, w, h, rgb) {
        this.Flush()
        r := Buffer(16)
        NumPut("Int", Round(x), "Int", Round(y), "Int", Round(x + w), "Int", Round(y + h), r)
        brush := DllCall("CreateSolidBrush", "UInt", Look.ColorRef(rgb), "Ptr")
        DllCall("FillRect", "Ptr", this.dc, "Ptr", r, "Ptr", brush)
        DllCall("DeleteObject", "Ptr", brush)
    }

    ; A rounded rectangle with corner radius ``r``, inside a ``border`` ``bw`` pixels wide if given.
    RoundRect(x, y, w, h, r, fill, border := "", bw := 1) {
        if border != "" {
            this._Round(x, y, w, h, r, border)
            x += bw, y += bw, w -= 2 * bw, h -= 2 * bw, r := Max(0, r - bw)
        }
        this._Round(x, y, w, h, r, fill)
    }

    _Round(x, y, w, h, r, rgb) {
        if w <= 0 || h <= 0
            return
        Canvas.Checked(DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &path := 0), "GdipCreatePath")
        r := Min(r, w / 2, h / 2)
        if r > 0 {
            d := 2 * r
            DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x, "Float", y, "Float", d, "Float", d, "Float", 180, "Float", 90)
            DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x + w - d, "Float", y, "Float", d, "Float", d, "Float", 270, "Float", 90)
            DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x + w - d, "Float", y + h - d, "Float", d, "Float", d, "Float", 0, "Float", 90)
            DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x, "Float", y + h - d, "Float", d, "Float", d, "Float", 90, "Float", 90)
            DllCall("gdiplus\GdipClosePathFigure", "Ptr", path)
        } else {
            DllCall("gdiplus\GdipAddPathRectangle", "Ptr", path, "Float", x, "Float", y, "Float", w, "Float", h)
        }
        brush := Canvas._Brush(rgb)
        Canvas.Checked(DllCall("gdiplus\GdipFillPath", "Ptr", this.Graphics, "Ptr", brush, "Ptr", path), "GdipFillPath")
        DllCall("gdiplus\GdipDeleteBrush", "Ptr", brush)
        DllCall("gdiplus\GdipDeletePath", "Ptr", path)
    }

    ; A line ``width`` pixels wide through ``points`` (x1, y1, x2, y2, ...) with
    ; round joins, and round ends if ``roundEnds``.
    Lines(points, width, rgb, roundEnds := false) {
        Canvas.Checked(DllCall("gdiplus\GdipCreatePen1", "UInt", Look.Argb(rgb), "Float", width, "Int", 2, "Ptr*", &pen := 0), "GdipCreatePen1")  ; UnitPixel
        DllCall("gdiplus\GdipSetPenLineJoin", "Ptr", pen, "Int", 2)  ; round
        if roundEnds {
            DllCall("gdiplus\GdipSetPenStartCap", "Ptr", pen, "Int", 2)
            DllCall("gdiplus\GdipSetPenEndCap", "Ptr", pen, "Int", 2)
        }
        Canvas.Checked(DllCall("gdiplus\GdipDrawLines", "Ptr", this.Graphics, "Ptr", pen, "Ptr", Canvas._Points(points), "Int", points.Length // 2), "GdipDrawLines")
        DllCall("gdiplus\GdipDeletePen", "Ptr", pen)
    }

    ; A filled shape through ``points`` (x1, y1, x2, y2, ...).
    Polygon(points, rgb) {
        brush := Canvas._Brush(rgb)
        Canvas.Checked(DllCall("gdiplus\GdipFillPolygon", "Ptr", this.Graphics, "Ptr", brush, "Ptr", Canvas._Points(points), "Int", points.Length // 2, "Int", 1), "GdipFillPolygon")
        DllCall("gdiplus\GdipDeleteBrush", "Ptr", brush)
    }

    ; ``text`` in ``font`` with its baseline at ``y``, starting at ``x`` (or
    ; centred on it, or ending at it, as ``align`` says).
    Text(text, font, rgb, x, y, align := "left") {
        this.Flush()
        old := DllCall("SelectObject", "Ptr", this.dc, "Ptr", font.handle, "Ptr")
        DllCall("SetTextColor", "Ptr", this.dc, "UInt", Look.ColorRef(rgb))
        DllCall("SetTextAlign", "Ptr", this.dc, "UInt", 24 | (align = "center" ? 6 : align = "right" ? 2 : 0))  ; TA_BASELINE
        DllCall("TextOutW", "Ptr", this.dc, "Int", Round(x), "Int", Round(y), "Str", text, "Int", StrLen(text))
        DllCall("SelectObject", "Ptr", this.dc, "Ptr", old)
    }

    ; A 1-pixel outline (the keyboard focus ring).
    Outline(x, y, w, h, rgb) {
        this.Rect(x, y, w, 1, rgb), this.Rect(x, y + h - 1, w, 1, rgb)
        this.Rect(x, y, 1, h, rgb), this.Rect(x + w - 1, y, 1, h, rgb)
    }

    ; Copies the picture onto a window's drawing surface.
    Paint(dc, x := 0, y := 0) {
        this.Flush()
        DllCall("BitBlt", "Ptr", dc, "Int", x, "Int", y, "Int", this.w, "Int", this.h, "Ptr", this.dc, "Int", 0, "Int", 0, "UInt", 0x00CC0020)
    }

    ; The colour of one pixel, 0xRRGGBB (tests).
    Pixel(x, y) => NumGet(this.bits, (y * this.w + x) * 4, "UInt") & 0xFFFFFF

    ; Saves the picture as a PNG file (checking the look).
    Save(path) {
        this.Flush()
        Gdip.SavePng(this.hbm, path)
    }

    ; Drawing that went wrong without stopping the window: GDI+ calls that
    ; failed, so Windows left that shape out, and painters that threw. Tests
    ; and CI check it stays empty. Only the first 20 are kept.
    static failures := []

    ; Notes a failure if ``status``, from the GDI+ call ``what``, isn't 0 (Ok).
    static Checked(status, what) {
        if status
            Canvas.Failed(what " (GDI+ status " status ")")
        return status
    }

    static Failed(text) {
        if Canvas.failures.Length < 20
            Canvas.failures.Push(text)
    }

    static _Brush(rgb) {
        Canvas.Checked(DllCall("gdiplus\GdipCreateSolidFill", "UInt", Look.Argb(rgb), "Ptr*", &brush := 0), "GdipCreateSolidFill")
        return brush
    }

    static _Points(points) {
        buf := Buffer(points.Length * 4)
        for v in points
            NumPut("Float", v, buf, (A_Index - 1) * 4)
        return buf
    }
}

; Controls SynSeeder draws itself (owner-drawn), and links. Each drawn
; control has a paint function, called with a Canvas of the control's size
; and its state: {hot (mouse over it), down (pressed), focus (from the
; keyboard), disabled}.
class Skin {
    static painters := Map()  ; control hwnd -> paint(canvas, state)
    static links := Map()     ; link hwnd -> {ctrl, font, normal, hover}
    static hot := 0           ; the control under the mouse
    static started := false
    static closing := false   ; the script is exiting: nothing more to draw

    static Start() {
        if Skin.started
            return
        Skin.started := true
        OnMessage(0x2B, ObjBindMethod(Skin, "_Draw"))      ; WM_DRAWITEM
        OnMessage(0x200, ObjBindMethod(Skin, "_Move"))     ; WM_MOUSEMOVE
        OnMessage(0x2A3, ObjBindMethod(Skin, "_Leave"))    ; WM_MOUSELEAVE
        OnMessage(0x20, ObjBindMethod(Skin, "_Cursor"))    ; WM_SETCURSOR
        OnExit((*) => (Skin.closing := true, ""))
    }

    ; An owner-drawn control (a Button with style 0xB, or a Text with 0xD) painted by ``paint``.
    static Add(ctrl, paint) {
        Skin.Start()
        Skin.painters[ctrl.Hwnd] := paint
        return ctrl
    }

    ; A Text control that works as a link: a hand pointer, and ``hover`` colour under the mouse.
    static Link(ctrl, font, normal, hover) {
        Skin.Start()
        Skin.links[ctrl.Hwnd] := {ctrl: ctrl, font: font, normal: normal, hover: hover}
        return ctrl
    }

    static Forget(ctrl) {
        for list in [Skin.painters, Skin.links]
            if list.Has(ctrl.Hwnd)
                list.Delete(ctrl.Hwnd)
        if Skin.hot = ctrl.Hwnd
            Skin.hot := 0
    }

    static Redraw(hwnd) => DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", false)

    static _Draw(wParam, lParam, msg, hwnd) {
        item := NumGet(lParam, 16 + A_PtrSize, "Ptr")
        if Skin.closing || !Skin.painters.Has(item)
            return
        flags := NumGet(lParam, 16, "UInt")
        dc := NumGet(lParam, 16 + 2 * A_PtrSize, "Ptr")
        rc := 16 + 3 * A_PtrSize
        left := NumGet(lParam, rc, "Int"), top := NumGet(lParam, rc + 4, "Int")
        w := NumGet(lParam, rc + 8, "Int") - left, h := NumGet(lParam, rc + 12, "Int") - top
        state := {hot: item = Skin.hot, down: (flags & 1) != 0, disabled: (flags & 4) != 0
            , focus: (flags & 0x10) && !(flags & 0x200)}  ; ODS_FOCUS, unless Windows hides focus until a key is pressed
        try {
            pic := Canvas(w, h, Look.TWILIGHT)
            Skin.painters[item](pic, state)
            pic.Paint(dc, left, top)
        } catch as err {
            Logs.Exception("Couldn't draw part of the window", err)
            Canvas.Failed("a painter threw " Type(err) ": " err.Message)
        }
        return true
    }

    static _Move(wParam, lParam, msg, hwnd) {
        target := Skin.painters.Has(hwnd) || Skin.links.Has(hwnd) ? hwnd : 0
        if target = Skin.hot
            return
        old := Skin.hot
        Skin.hot := target
        if old
            Skin._Show(old, false)
        if target {
            tme := Buffer(8 + 2 * A_PtrSize, 0)  ; TRACKMOUSEEVENT, for a WM_MOUSELEAVE
            NumPut("UInt", tme.Size, tme, 0), NumPut("UInt", 2, tme, 4), NumPut("Ptr", target, tme, 8)
            DllCall("TrackMouseEvent", "Ptr", tme)
            Skin._Show(target, true)
        }
    }

    static _Leave(wParam, lParam, msg, hwnd) {
        if hwnd = Skin.hot {
            Skin.hot := 0
            Skin._Show(hwnd, false)
        }
    }

    static _Show(hwnd, hot) {
        if Skin.links.Has(hwnd) {
            link := Skin.links[hwnd]
            try link.ctrl.SetFont("c" Look.Hex(hot ? link.hover : link.normal))
        } else {
            Skin.Redraw(hwnd)
        }
    }

    static _Cursor(wParam, lParam, msg, hwnd) {
        if Skin.links.Has(wParam) {
            DllCall("SetCursor", "Ptr", DllCall("LoadCursorW", "Ptr", 0, "Ptr", 32649, "Ptr"))  ; IDC_HAND
            return true
        }
    }
}

; What the window's parts look like.
class Paint {
    ; The header: the seedling and the app's name, centred on a dusk sky, over a line of first light.
    static Header(canvas, titleFont) {
        s := Look.scale, w := canvas.w, h := canvas.h
        ; The sky, with an ember glow blurred up from the bottom edge. Pillow
        ; blurred the glow's colour together with the transparent black round
        ; it, which darkens its fringe: hence k twice.
        glow := 0.11, sigma := h * glow / 2, edge := h * (1 - glow)
        loop h {
            y := A_Index - 1
            sky := Look.Along(Look.DUSK, (y + 0.5) / h)
            k := Look.NormalCdf((y + 0.5 - edge) / sigma)
            a := 160 / 255 * k
            color := 0
            for shift in [16, 8, 0]
                color |= Min(255, Round((Look.EMBER >> shift & 0xFF) * k * a + (sky >> shift & 0xFF) * (1 - a))) << shift
            canvas.Rect(0, y, w, 1, color)
        }
        line := Max(1, Round(2 * s))
        canvas.Rect(0, h - line, w, line, Look.FIRST_LIGHT)

        ; The seedling and the title, centred together.
        bearings := titleFont.Bearings(Look.TITLE)
        ink := titleFont.Width(Look.TITLE) - bearings[1] - bearings[2]
        markW := (55 - 8) * Look.MARK_UNIT * s  ; the leaves span x 8..55 of the seedling's box
        x := (w - (markW + Look.MARK_GAP * s + ink)) / 2
        Paint.Seedling(canvas, x - 8 * Look.MARK_UNIT * s, Look.MARK_Y * s, Look.MARK_UNIT * s)
        canvas.Text(Look.TITLE, titleFont, Look.HAZE, x + markW + Look.MARK_GAP * s - bearings[1], (Look.TITLE_Y + Look.TITLE_SIZE) * s)
    }

    ; A two-leaf seedling like the 🌱 emoji, in a 64-unit box at (ox, oy), ``u`` pixels a unit.
    static Seedling(canvas, ox, oy, u) {
        p(x, y) => [ox + x * u, oy + y * u]
        stem := []
        for q in Look.Bezier([32, 56], [33.6, 43], [31.6, 30], 40)
            stem.Push(p(q[1], q[2]))
        Paint._Tapered(canvas, stem, 4.4 * u, 3.0 * u, Look.SPROUT_GREEN)
        vein := Max(1, Round(1.1 * u * 4)) / 4
        for leaf in [[31.5, 32.5, 8, 19, 9.5, 1.5], [32, 30.5, 55, 11, 10.5, -2.0]]
            Paint._Leaf(canvas, p(leaf[1], leaf[2]), p(leaf[3], leaf[4]), leaf[5] * u, leaf[6] * u, vein)
    }

    ; A shape along ``points`` whose width goes from ``w0`` to ``w1``.
    static _Tapered(canvas, points, w0, w1, rgb) {
        n := points.Length, left := [], right := []
        for i, q in points {
            a := points[Max(1, i - 1)], b := points[Min(n, i + 1)]
            dx := b[1] - a[1], dy := b[2] - a[2]
            length := Sqrt(dx * dx + dy * dy) || 1
            nx := -dy / length, ny := dx / length
            half := (w0 + (w1 - w0) * (i - 1) / (n - 1)) / 2
            left.Push(q[1] + nx * half, q[2] + ny * half)
            right.InsertAt(1, q[1] - nx * half, q[2] - ny * half)
        }
        left.Push(right*)
        canvas.Polygon(left, rgb)
    }

    ; An almond-shaped leaf from ``base`` to ``tip``; ``bend`` curves it sideways. Has a vein ``vein`` pixels wide.
    static _Leaf(canvas, base, tip, width, bend, vein) {
        length := Sqrt((tip[1] - base[1]) ** 2 + (tip[2] - base[2]) ** 2)
        nx := -(tip[2] - base[2]) / length, ny := (tip[1] - base[1]) / length
        mx := (base[1] + tip[1]) / 2 + nx * bend, my := (base[2] + tip[2]) / 2 + ny * bend
        outline := []
        for q in Look.Bezier(base, [mx + nx * width, my + ny * width], tip, 40)
            outline.Push(q[1], q[2])
        for q in Look.Bezier(tip, [mx - nx * width, my - ny * width], base, 40)
            outline.Push(q[1], q[2])
        canvas.Polygon(outline, Look.SPROUT_GREEN)
        rib := []
        for q in Look.Bezier(base, [mx + nx * width * 0.15, my + ny * width * 0.15], tip, 40)
            if A_Index <= 33
                rib.Push(q[1], q[2])
        canvas.Lines(rib, vein, Look.SPROUT_VEIN)
    }

    ; The player count, how far the server is from seeded, and a thin meter
    ; of players out of ``most`` with a tick where it counts as seeded.
    ; ``count`` is "" until it's known, with ``note`` saying why.
    static Players(canvas, fonts, count, note, threshold, most, lineHeight) {
        s := Look.scale, w := canvas.w, pad := Look.Px(2)
        base := pad + fonts.count.ascent
        if count = "" {
            canvas.Text(note, fonts.body, Look.MIST, pad, base)
        } else {
            canvas.Text(count, fonts.count, Look.HAZE, pad, base)
            canvas.Text("of " most " players right now", fonts.body, Look.MIST, pad + fonts.count.Width(count) + Look.Px(6) + pad, base)
            missing := threshold - count
            canvas.Text(missing > 0 ? "Needs " missing " more" : "Seeded", fonts.semibold, missing > 0 ? Look.FIRST_LIGHT : Look.PADDY, w - pad, base, "right")
        }

        top := lineHeight + Look.Px(6)
        thick := 6 * s, y := top + 7 * s, left := thick / 2, right := w - thick / 2
        canvas.Lines([left, y, right, y], thick, Look.TRACK, true)
        if count != "" && count > 0
            canvas.Lines([left, y, left + (right - left) * Min(count, most) / most, y], thick, count >= threshold ? Look.PADDY : Look.FIRST_LIGHT, true)
        tick := Round(left + (right - left) * Min(Max(threshold, 0), most) / most)
        canvas.Rect(tick - Look.Px(1), top + Look.Px(1), Look.Px(2), Look.Px(12), Look.HAZE)
        label := "Seeded at " threshold, labelW := fonts.small.Width(label)
        canvas.Text(label, fonts.small, Look.MIST, Paint.LabelX(tick, labelW, w), top + Look.Px(15) + fonts.small.ascent)
    }

    ; Where a label ``labelW`` wide starts, centred on ``x`` but kept on a meter ``w`` wide.
    static LabelX(x, labelW, w) => Max(0, Min(x - labelW / 2, w - labelW))

    ; Save (``primary``), Seed now and Stop seeding.
    static Button(canvas, text, font, primary, state) {
        s := Look.scale, w := canvas.w, h := canvas.h, r := 5 * s
        if primary {
            if state.disabled
                canvas.RoundRect(0, 0, w, h, r, 0x5A4A33)
            else if state.down
                canvas.RoundRect(0, 0, w, h, r, 0xD98C2E)
            else if state.hot
                canvas.RoundRect(0, 0, w, h, r, 0xF7B65E)
            else if state.focus
                canvas.RoundRect(0, 0, w, h, r, Look.FIRST_LIGHT, 0xFFE3B3, 1.5 * s)
            else
                canvas.RoundRect(0, 0, w, h, r, Look.FIRST_LIGHT)
            color := state.disabled ? Look.MIST : Look.INK
        } else {
            if state.disabled
                canvas.RoundRect(0, 0, w, h, r, Look.TWILIGHT, 0x262A3B, s)
            else if state.down
                canvas.RoundRect(0, 0, w, h, r, 0x121624, 0x555B78, s)
            else if state.hot
                canvas.RoundRect(0, 0, w, h, r, 0x292E45, 0x555B78, s)
            else if state.focus
                canvas.RoundRect(0, 0, w, h, r, Look.SLATE, Look.FOCUS, 1.5 * s)
            else
                canvas.RoundRect(0, 0, w, h, r, Look.SLATE, Look.EDGE, s)
            color := state.disabled ? Look.MIST : Look.HAZE
        }
        canvas.Text(text, font, color, w / 2, Ceil((h - font.height) / 2) + font.ascent, "center")
    }

    ; Steam or Epic: one of two chips, ``on`` when it's the launcher chosen.
    static Chip(canvas, text, font, on, state) {
        s := Look.scale, w := canvas.w, h := canvas.h, r := 4 * s
        if on && state.focus
            canvas.RoundRect(0, 0, w, h, r, 0x3A2F1D, 0xFFE3B3, 1.5 * s)
        else if on
            canvas.RoundRect(0, 0, w, h, r, 0x3A2F1D, Look.FIRST_LIGHT, 1.5 * s)
        else if state.hot
            canvas.RoundRect(0, 0, w, h, r, 0x1E2234, 0x555B78, s)
        else if state.focus
            canvas.RoundRect(0, 0, w, h, r, Look.TWILIGHT, Look.FOCUS, 1.5 * s)
        else
            canvas.RoundRect(0, 0, w, h, r, Look.TWILIGHT, Look.EDGE, s)
        canvas.Text(text, font, on || state.hot ? Look.HAZE : Look.MIST, w / 2, Ceil((h - font.height) / 2) + font.ascent, "center")
    }

    ; An hour or minute picker: the value, and a chevron that says it drops down.
    static Field(canvas, text, font, state) {
        s := Look.scale, w := canvas.w, h := canvas.h, r := 4 * s
        if state.focus
            canvas.RoundRect(0, 0, w, h, r, Look.SLATE, Look.FOCUS, 1.5 * s)
        else if state.hot || state.down
            canvas.RoundRect(0, 0, w, h, r, 0x262A3F, 0x555B78, s)
        else
            canvas.RoundRect(0, 0, w, h, r, Look.SLATE, Look.EDGE, s)
        canvas.Text(text, font, Look.HAZE, 10 * s, Ceil((h - font.height) / 2) + font.ascent)
        x := w - 22 * s, y := (h - 16 * s) / 2
        canvas.Lines([x + 5.5 * s, y + 6.2 * s, x + 9.5 * s, y + 10.2 * s, x + 13.5 * s, y + 6.2 * s], 1.8 * s, Look.HAZE, true)
    }

    ; "Seed automatically": the label on the left, its box against the right edge.
    static Check(canvas, text, font, on, state, baseline) {
        s := Look.scale, w := canvas.w, pad := Look.Px(1)
        canvas.Text(text, font, Look.HAZE, pad, baseline)
        if state.focus
            canvas.Outline(0, baseline - font.ascent - pad, font.Width(text) + 2 * pad, font.height + 2 * pad, Look.FOCUS)
        box := 18 * s, x := w - Look.Px(1) - box, y := Round((canvas.h - box) / 2) - Look.Px(1)
        if on {
            canvas.RoundRect(x + s, y + s, 16 * s, 16 * s, 3 * s, state.hot ? 0xF7B65E : Look.FIRST_LIGHT)
            canvas.Lines([x + 5.0 * s, y + 9.4 * s, x + 7.9 * s, y + 12.2 * s, x + 13.2 * s, y + 6.2 * s], 2.1 * s, Look.INK, true)
        } else {
            canvas.RoundRect(x + s, y + s, 16 * s, 16 * s, 3 * s, state.hot ? Look.MIST : 0x666A85)
            canvas.RoundRect(x + 2.5 * s, y + 2.5 * s, 13 * s, 13 * s, 2 * s, Look.SLATE)
        }
    }

    ; The grid of hours or minutes under a picker: ``chosen`` is the value it
    ; has, ``hot`` the one under the mouse or the keyboard's cursor (indexes).
    static Grid(canvas, values, columns, cell, font, chosen, hot) {
        s := Look.scale, inset := Look.Px(4)
        canvas.Rect(0, 0, canvas.w, canvas.h, Look.EDGE)
        canvas.Rect(1, 1, canvas.w - 2, canvas.h - 2, Look.SLATE)
        for value in values {
            i := A_Index - 1
            x := inset + Mod(i, columns) * cell.w, y := inset + (i // columns) * cell.h
            color := Look.HAZE
            if A_Index = chosen
                canvas.RoundRect(x + s, y + s, cell.w - 2 * s, cell.h - 2 * s, 4 * s, A_Index = hot ? 0xF7B65E : Look.FIRST_LIGHT), color := Look.INK
            else if A_Index = hot
                canvas.RoundRect(x + s, y + s, cell.w - 2 * s, cell.h - 2 * s, 4 * s, 0x2C314A, 0x555B78, s)
            canvas.Text(value, font, color, x + cell.w / 2, y + Ceil((cell.h - font.height) / 2) + font.ascent, "center")
        }
    }
}
