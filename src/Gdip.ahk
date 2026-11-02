; Reading and writing image files with GDI+, which comes with Windows.

class Gdip {
    static token := 0

    static Start() {
        if Gdip.token
            return
        DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
        input := Buffer(24, 0)  ; GdiplusStartupInput
        NumPut("UInt", 1, input)
        status := DllCall("gdiplus\GdiplusStartup", "Ptr*", &token := 0, "Ptr", input, "Ptr", 0)
        if status
            throw OSError("Couldn't start GDI+ (status " status ")")
        Gdip.token := token
    }

    ; An image file's pixels as 32-bit BGRA: {buf, w, h, stride}.
    static LoadBits(path) {
        Gdip.Start()
        status := DllCall("gdiplus\GdipCreateBitmapFromFile", "WStr", path, "Ptr*", &bitmap := 0)
        if status || !bitmap
            throw OSError("Couldn't read the image " path " (GDI+ status " status ")")
        try
            return Gdip.Bits(bitmap)
        finally
            DllCall("gdiplus\GdipDisposeImage", "Ptr", bitmap)
    }

    ; A GDI+ bitmap's pixels as 32-bit BGRA: {buf, w, h, stride}.
    static Bits(bitmap) {
        DllCall("gdiplus\GdipGetImageWidth", "Ptr", bitmap, "UInt*", &w := 0)
        DllCall("gdiplus\GdipGetImageHeight", "Ptr", bitmap, "UInt*", &h := 0)
        buf := Buffer(w * h * 4)
        rect := Buffer(16, 0)
        NumPut("Int", w, rect, 8), NumPut("Int", h, rect, 12)
        data := Buffer(32, 0)  ; BitmapData, pointing GDI+ at our buffer
        NumPut("UInt", w, data, 0), NumPut("UInt", h, data, 4), NumPut("Int", w * 4, data, 8)
        NumPut("Int", 0x26200A, data, 12), NumPut("Ptr", buf.Ptr, data, 16)
        ; ImageLockModeRead | ImageLockModeUserInputBuf, as PixelFormat32bppARGB
        status := DllCall("gdiplus\GdipBitmapLockBits", "Ptr", bitmap, "Ptr", rect, "UInt", 5, "Int", 0x26200A, "Ptr", data)
        if status
            throw OSError("Couldn't read an image's pixels (GDI+ status " status ")")
        DllCall("gdiplus\GdipBitmapUnlockBits", "Ptr", bitmap, "Ptr", data)
        return {buf: buf, w: w, h: h, stride: w * 4}
    }

    ; Saves a GDI bitmap (HBITMAP) as a PNG file.
    static SavePng(hbitmap, path) {
        Gdip.Start()
        status := DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "Ptr", hbitmap, "Ptr", 0, "Ptr*", &bitmap := 0)
        if status || !bitmap
            throw OSError("Couldn't copy the screenshot (GDI+ status " status ")")
        try {
            clsid := Buffer(16)
            DllCall("ole32\CLSIDFromString", "WStr", "{557CF406-1A04-11D3-9A73-0000F81EF32E}", "Ptr", clsid)  ; PNG encoder
            status := DllCall("gdiplus\GdipSaveImageToFile", "Ptr", bitmap, "WStr", path, "Ptr", clsid, "Ptr", 0)
            if status
                throw OSError("Couldn't save " path " (GDI+ status " status ")")
        } finally {
            DllCall("gdiplus\GdipDisposeImage", "Ptr", bitmap)
        }
    }
}
