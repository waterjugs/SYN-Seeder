; Self-update for the "full" trial: downloads a newer SynSeeder.exe from
; GitHub and lets it copy itself over this one.

; Run by the new version: "--install-to <old exe>" copies itself over the old one and starts it.
HandleUpdateArgs() {
    if A_Args.Length < 2 || A_Args[1] != "--install-to"
        return false
    target := A_Args[2]
    loop 30 {
        try {
            FileCopy A_ScriptFullPath, target, 1
            break
        }
        Sleep 2000
    }
    Run '"' target '"'
    return true
}

CheckForUpdates(*) {
    try {
        text := HttpGet(RELEASE_API, "application/vnd.github+json").ResponseText
    } catch {
        UI.Status.Value := "Couldn't check for updates."
        return
    }
    if !RegExMatch(text, '"tag_name"\s*:\s*"v?([\d.]+)"', &tag) || VerCompare(tag[1], APP_VERSION) <= 0 {
        UI.Status.Value := "You have the latest version."
        return
    }
    if !RegExMatch(text, '"browser_download_url"\s*:\s*"(https://[^"]+/SynSeeder\.exe)"', &url) {
        UI.Status.Value := "v" tag[1] " is out, but has no SynSeeder.exe yet."
        return
    }
    UI.Status.Value := "Downloading v" tag[1] "..."
    fresh := DATA_DIR "\SynSeeder-update.exe"
    DirCreate DATA_DIR
    SaveBody(HttpGet(url[1], "application/octet-stream"), fresh)
    Run '"' fresh '" --install-to "' A_ScriptFullPath '"'
    ExitApp
}

; Writes a WinHttp response body (an array of bytes) to a file.
SaveBody(req, path) {
    body := req.ResponseBody
    size := body.MaxIndex() + 1
    data := NumGet(ComObjValue(body), 8 + A_PtrSize, "Ptr")  ; the array's data pointer
    f := FileOpen(path, "w")
    f.RawWrite(data, size)
    f.Close()
}
