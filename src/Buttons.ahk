; The button images the seeder looks for (templates/*.png in the repository).

class Buttons {
    ; Loads the button images in ``folders`` for Vision: a Map of name -> Array of
    ; {img, cut, tag}. A button with images in a later folder gets only those, so
    ; players can drop in fixes. In each folder, files are taken in name order.
    static Load(folders*) {
        crops := Map()
        for folder in folders {
            if folder = "" || !DirExist(folder)
                continue
            names := ""
            loop files folder "\*.png"
                names .= A_LoopFileName "`n"
            if names = ""
                continue
            replaced := Map()
            for fileName in StrSplit(Sort(RTrim(names, "`n"), "C"), "`n") {
                info := Buttons.Parse(fileName)
                try
                    img := Buttons.Gray(folder "\" fileName)
                catch
                    continue
                if !replaced.Has(info.name) {
                    crops[info.name] := []
                    replaced[info.name] := true
                }
                crops[info.name].Push({img: img, cut: info.cut, tag: info.tag})
            }
        }
        return crops
    }

    ; What a file name says: "server_row.1080p.png" is server_row cut from a
    ; 1080-pixel-high screen; "roles_confirm.title.png" is another part of
    ; roles_confirm's screen ("title"), cut from a 1440-pixel-high one.
    static Parse(file) {
        parts := StrSplit(RegExReplace(file, "i)\.png$"), ".")
        cut := 1440, tag := ""
        if parts.Length > 1 {
            last := parts[parts.Length]
            if RegExMatch(last, "^(\d{3,4})p$", &m)
                cut := Integer(m[1])
            else
                tag := last
        }
        return {name: parts[1], cut: cut, tag: tag}
    }

    ; An image file in gray, as OpenCV's BGR2GRAY does it.
    static Gray(path) {
        bits := Gdip.LoadBits(path)
        img := VisionGray(bits.w, bits.h)
        sp := bits.buf.Ptr, op := img.buf.Ptr
        loop bits.w * bits.h {
            v := NumGet(sp, "UInt"), sp += 4
            NumPut("UChar", ((v >> 16 & 255) * 4899 + (v >> 8 & 255) * 9617 + (v & 255) * 1868 + 8192) >> 14, op++)
        }
        return img
    }

    ; Names of required buttons with no image in ``crops``.
    static Missing(crops) {
        out := []
        for name in Vision.REQUIRED
            if !crops.Has(name) || !crops[name].Length
                out.Push(name)
        return out
    }
}
