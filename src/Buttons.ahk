; The button images the seeder looks for (templates/*.png in the repository).

class Buttons {
    ; Loads the button images in ``folder`` for Vision: a Map of name -> Array
    ; of {img, cut, tag}, taking files in name order. ``only`` limits it to the
    ; file names a Map has as keys.
    static Load(folder, only := "") {
        crops := Map()
        if folder = "" || !DirExist(folder)
            return crops
        names := ""
        loop files folder "\*.png"
            if !(only is Map) || only.Has(A_LoopFileName)
                names .= A_LoopFileName "`n"
        if names = ""
            return crops
        for fileName in StrSplit(Sort(RTrim(names, "`n"), "C"), "`n") {
            info := Buttons.Parse(fileName)
            try
                img := Buttons.Gray(folder "\" fileName)
            catch as err {
                Logs.Warning("Couldn't read the button image " fileName ": " err.Message)
                continue
            }
            if !crops.Has(info.name)
                crops[info.name] := []
            crops[info.name].Push({img: img, cut: info.cut, tag: info.tag})
        }
        return crops
    }

    ; ``base`` with every button that ``overrides`` has images of replaced by those.
    static Merge(base, overrides) {
        out := Map()
        for name, list in base
            out[name] := list
        for name, list in overrides
            out[name] := list
        return out
    }

    ; Where a built SynSeeder.exe keeps the button images it downloads.
    static Folder => App.InstallDir "\buttons"

    ; Makes sure ``folder`` holds every file in ``files`` (name -> SHA-256),
    ; downloading missing or changed ones from the repository at ``ref`` (a
    ; commit, or a branch for a build made outside CI). A download is only kept
    ; if its checksum matches. Returns the names it couldn't get.
    static Fetch(folder, files, ref) {
        DirCreate(folder)
        missing := []
        for fileName, sha in files {
            path := folder "\" fileName
            if FileExist(path) && Sha256.File(path) = sha
                continue
            temp := path ".part"
            try {
                Http.Download("https://raw.githubusercontent.com/" App.REPO "/" ref "/templates/" fileName, temp, "image/png", 30)
                if Sha256.File(temp) = sha {
                    FileMove(temp, path, true)
                    continue
                }
                Logs.Warning("Downloaded " fileName ", but it isn't the right file; not using it")
            } catch as err {
                Logs.Warning("Couldn't download the button image " fileName ": " err.Message)
            }
            try FileDelete(temp)
            missing.Push(fileName)
        }
        return missing
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
