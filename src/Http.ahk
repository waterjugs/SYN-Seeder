; Talking to the internet: the server's stats page, GitHub's releases and the
; button images. Uses WinHTTP, which comes with Windows.

class Http {
    static agent := "SynSeeder"

    ; The response to a GET request, or throws if it can't be fetched or
    ; doesn't answer 200 OK. Redirects are followed.
    static Get(url, accept := "application/json", timeout := 15) => Http.Check(Http.Start(url, accept, timeout))

    ; Sends a GET request. With ``async``, returns at once: Http.Done(request)
    ; says when the answer is in. Without ``redirects``, an answer that sends
    ; the request somewhere else is taken as it is, not followed.
    static Start(url, accept := "application/json", timeout := 15, async := false, redirects := true) {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.Open("GET", url, async)
        if !redirects
            req.Option[6] := false  ; WinHttpRequestOption_EnableRedirects
        req.SetRequestHeader("User-Agent", Http.agent)
        req.SetRequestHeader("Accept", accept)
        ms := Round(timeout * 1000)
        req.SetTimeouts(ms, ms, ms, ms)  ; resolve, connect, send, receive
        req.Send()
        return req
    }

    ; True once a request from Http.Start(..., true) has its answer (or has failed).
    static Done(req) => req.WaitForResponse(0) != 0

    ; ``req``, or throws if it didn't answer 200 OK.
    static Check(req) {
        if req.Status != 200
            throw Error("HTTP " req.Status " " req.StatusText)
        return req
    }

    ; A response's body, read as UTF-8. ResponseBody is a new array each time,
    ; freed as soon as nothing holds it, so ``body`` keeps it until StrGet has
    ; copied the bytes.
    static BodyText(req) {
        body := req.ResponseBody
        data := Http._Bytes(body, &size)
        text := size ? StrGet(data, size, "UTF-8") : ""
        return text
    }

    ; The body of a GET request as text (read as UTF-8).
    static Text(url, accept := "application/json", timeout := 15) => Http.BodyText(Http.Get(url, accept, timeout))

    ; Like Text, for a page someone else runs. It gives up ``timeout`` seconds
    ; after asking, however slowly an answer trickles in (Get's time limits
    ; are for each step, so they never add up to one), and refuses an answer
    ; over ``maxBytes``. The script keeps taking its own messages while it
    ; waits, so a stop request isn't held up behind a slow page.
    static TextWithin(url, accept, timeout, maxBytes) {
        req := Http.Start(url, accept, timeout, true)
        deadline := A_TickCount + Round(timeout * 1000)
        while !Http.Done(req) {
            if A_TickCount >= deadline {
                try req.Abort()
                throw Error("no answer in " Format("{:g}", timeout) " seconds")
            }
            Sleep(20)
        }
        Http.Check(req)
        body := req.ResponseBody
        Http._Bytes(body, &size)
        if size > maxBytes
            throw Error("the answer is too big (" size " bytes)")
        return Http.BodyText(req)
    }

    ; Saves the body of a GET request to ``path``. Returns its size in bytes.
    static Download(url, path, accept := "application/octet-stream", timeout := 30) => Http.Save(Http.Get(url, accept, timeout), path)

    ; Saves a response's body to ``path``. Returns its size in bytes.
    static Save(req, path) {
        body := req.ResponseBody
        data := Http._Bytes(body, &size)
        out := FileOpen(path, "w")
        if !out
            throw OSError("Couldn't write " path)
        if size
            out.RawWrite(data, size)
        out.Close()
        return size
    }

    ; Where a response body's bytes are, and how many there are.
    static _Bytes(body, &size) {
        size := 0
        if !(body is ComObjArray)
            return 0
        size := body.MaxIndex() + 1
        ; a SAFEARRAY keeps its data pointer after cDims, fFeatures, cbElements and cLocks
        return size ? NumGet(ComObjValue(body), 8 + A_PtrSize, "Ptr") : 0
    }
}

; Files SynSeeder downloads from its GitHub repository, rather than carrying
; them inside the exe: the button images and the window's fonts. A download
; is only kept if its checksum matches, and is saved under a name of this
; process's own until then, so two SynSeeders fetching at once can't mix
; their files up.
class RepoFiles {
    ; Where ``fileName`` in ``path`` is in the repository at ``ref`` (a commit,
    ; or a branch for a build made outside CI).
    static Url(ref, path, fileName) => "https://raw.githubusercontent.com/" App.REPO "/" ref "/" path "/" fileName

    ; Makes sure ``folder`` holds every file in ``files`` (name -> SHA-256),
    ; downloading missing or changed ones from ``path`` in the repository at
    ; ``ref``, one at a time. A file that doesn't match and can't be replaced
    ; is deleted. ``what`` names the files in the log. With ``giveUp``, stops
    ; at the first file it can't get. Returns the names it couldn't get.
    static Fetch(folder, files, ref, path, what, timeout := 30, giveUp := false) {
        DirCreate(folder)
        missing := []
        for fileName, sha in files {
            target := folder "\" fileName
            if Sha256.File(target) = sha
                continue
            if giveUp && missing.Length {
                missing.Push(fileName)
                continue
            }
            temp := RepoFiles._Temp(target)
            try {
                Http.Download(RepoFiles.Url(ref, path, fileName), temp, "application/octet-stream", timeout)
                RepoFiles._Keep(temp, target, sha)
            } catch as err {
                Logs.Warning("Couldn't download the " what " " fileName ": " err.Message)
                RepoFiles._Drop(temp, target, sha)
                missing.Push(fileName)
            }
        }
        return missing
    }

    ; Like Fetch, but downloads them all at once and waits ``wait`` seconds at
    ; most in all, giving up on any that haven't come by then.
    static FetchAtOnce(folder, files, ref, path, what, wait) {
        DirCreate(folder)
        missing := [], pending := Map()
        for fileName, sha in files {
            if Sha256.File(folder "\" fileName) = sha
                continue
            try {
                pending[fileName] := Http.Start(RepoFiles.Url(ref, path, fileName), "application/octet-stream", wait, true)
            } catch as err {
                Logs.Warning("Couldn't download the " what " " fileName ": " err.Message)
                RepoFiles._Drop("", folder "\" fileName, sha)
                missing.Push(fileName)
            }
        }
        deadline := A_TickCount + Round(wait * 1000)
        while pending.Count {
            names := []
            for fileName in pending
                names.Push(fileName)
            for fileName in names {
                req := pending[fileName], target := folder "\" fileName, temp := RepoFiles._Temp(target)
                try {
                    if !Http.Done(req) {
                        if A_TickCount < deadline
                            continue
                        try req.Abort()
                        throw Error("no answer in " Format("{:g}", wait) " seconds")
                    }
                    Http.Save(Http.Check(req), temp)
                    RepoFiles._Keep(temp, target, files[fileName])
                } catch as err {
                    Logs.Warning("Couldn't download the " what " " fileName ": " err.Message)
                    RepoFiles._Drop(temp, target, files[fileName])
                    missing.Push(fileName)
                }
                pending.Delete(fileName)
            }
            if pending.Count
                Sleep(20)
        }
        return missing
    }

    ; This process's name for a download of ``target`` until it's checked.
    static _Temp(target) => target "." DllCall("GetCurrentProcessId", "UInt") ".part"

    ; Puts the download ``temp`` in place as ``target`` if its checksum is ``sha``; throws if it isn't.
    static _Keep(temp, target, sha) {
        if Sha256.File(temp) != sha
            throw Error("the download isn't the right file")
        FileMove(temp, target, true)
    }

    ; Clears up after a failed download: its temp file, and an old or changed
    ; copy of the file, which would never be used.
    static _Drop(temp, target, sha) {
        if temp != ""
            try FileDelete(temp)
        if FileExist(target) && Sha256.File(target) != sha
            try FileDelete(target)
    }
}

; The server's population, from its CRCON public info page.
class ServerStats {
    static MAX_BYTES := 1024 * 1024  ; a real answer is a few hundred bytes

    ; {name, players, allied, axis, timeRemaining} from the page's JSON. Throws if it reports a failure.
    static Parse(payload) {
        if !(payload is Map)
            throw ValueError("the stats page didn't send a JSON object")
        result := payload.Has("result") ? payload["result"] : ""
        failed := payload.Has("failed") && payload["failed"]
        if failed || !(result is Map) {
            reason := payload.Has("error") && payload["error"] != "" ? payload["error"] : "no result"
            throw ValueError("CRCON reported a failure: " (IsObject(reason) ? Json.Dump(reason) : reason))
        }
        teams := result.Has("player_count_by_team") && result["player_count_by_team"] is Map ? result["player_count_by_team"] : Map()
        name := result.Has("name") ? result["name"] : ""
        if name is Map
            name := name.Has("name") ? name["name"] : ""
        if !result.Has("player_count")
            throw ValueError("the stats page has no player count")
        return {
            name: String(name),
            players: Integer(result["player_count"]),
            allied: Integer(teams.Has("allied") ? teams["allied"] : 0),
            axis: Integer(teams.Has("axis") ? teams["axis"] : 0),
            timeRemaining: Float(result.Has("time_remaining") && result["time_remaining"] != "" ? result["time_remaining"] : 0)
        }
    }

    ; The server's status, or "" when the server or the page can't be reached,
    ; doesn't answer within ``timeout`` seconds, or sends far too much.
    static Fetch(url, timeout := 10) {
        try {
            return ServerStats.Read(Http.TextWithin(url, "application/json", timeout, ServerStats.MAX_BYTES))
        } catch as err {
            Logs.Warning("Could not read server status from " url ": " err.Message)
            return ""
        }
    }

    ; The status in the stats page's ``text``. Throws if it isn't one.
    static Read(text) => ServerStats.Parse(Json.Load(text))

    ; The team to join: the one with fewer players, allies on a tie.
    static WeakerSide(status) => status.allied <= status.axis ? "allies" : "axis"
}

; SHA-256 checksums, with Windows' own cryptography (bcrypt.dll).
class Sha256 {
    ; Lowercase hex checksum of a file, or "" if it can't be read.
    static File(path) {
        try
            source := FileOpen(path, "r")
        catch
            return ""
        if !source
            return ""
        chunk := Buffer(1 << 20)
        hash := Sha256._Start()
        try {
            while (n := source.RawRead(chunk, chunk.Size)) > 0
                DllCall("bcrypt\BCryptHashData", "Ptr", hash.handle, "Ptr", chunk, "UInt", n, "UInt", 0)
        } finally {
            source.Close()
        }
        return Sha256._Finish(hash)
    }

    ; Lowercase hex checksum of ``size`` bytes at ``ptr``.
    static Bytes(ptr, size) {
        hash := Sha256._Start()
        DllCall("bcrypt\BCryptHashData", "Ptr", hash.handle, "Ptr", ptr, "UInt", size, "UInt", 0)
        return Sha256._Finish(hash)
    }

    static Text(text) {
        data := Buffer(StrPut(text, "UTF-8") - 1)
        StrPut(text, data, "UTF-8")
        return Sha256.Bytes(data.Ptr, data.Size)
    }

    static _Start() {
        if DllCall("bcrypt\BCryptOpenAlgorithmProvider", "Ptr*", &alg := 0, "WStr", "SHA256", "Ptr", 0, "UInt", 0)
            throw OSError("Couldn't start SHA-256")
        if DllCall("bcrypt\BCryptCreateHash", "Ptr", alg, "Ptr*", &handle := 0, "Ptr", 0, "UInt", 0, "Ptr", 0, "UInt", 0, "UInt", 0) {
            DllCall("bcrypt\BCryptCloseAlgorithmProvider", "Ptr", alg, "UInt", 0)
            throw OSError("Couldn't start SHA-256")
        }
        return {alg: alg, handle: handle}
    }

    static _Finish(hash) {
        digest := Buffer(32)
        DllCall("bcrypt\BCryptFinishHash", "Ptr", hash.handle, "Ptr", digest, "UInt", 32, "UInt", 0)
        DllCall("bcrypt\BCryptDestroyHash", "Ptr", hash.handle)
        DllCall("bcrypt\BCryptCloseAlgorithmProvider", "Ptr", hash.alg, "UInt", 0)
        hex := ""
        loop 32
            hex .= Format("{:02x}", NumGet(digest, A_Index - 1, "UChar"))
        return hex
    }
}
