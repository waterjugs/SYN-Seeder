; Talking to the internet: the server's stats page, GitHub's releases and the
; button images. Uses WinHTTP, which comes with Windows.

class Http {
    static agent := "SynSeeder"

    ; The response to a GET request, or throws if it can't be fetched or
    ; doesn't answer 200 OK. Redirects are followed.
    static Get(url, accept := "application/json", timeout := 15) {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.Open("GET", url, false)
        req.SetRequestHeader("User-Agent", Http.agent)
        req.SetRequestHeader("Accept", accept)
        ms := Round(timeout * 1000)
        req.SetTimeouts(ms, ms, ms, ms)  ; resolve, connect, send, receive
        req.Send()
        if req.Status != 200
            throw Error("HTTP " req.Status " " req.StatusText)
        return req
    }

    ; The body of a GET request as text (read as UTF-8).
    static Text(url, accept := "application/json", timeout := 15) {
        body := Http.Get(url, accept, timeout).ResponseBody
        data := Http._Bytes(body, &size)
        return size ? StrGet(data, size, "UTF-8") : ""
    }

    ; Saves the body of a GET request to ``path``. Returns its size in bytes.
    static Download(url, path, accept := "application/octet-stream", timeout := 30) {
        body := Http.Get(url, accept, timeout).ResponseBody
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

; The server's population, from its CRCON public info page.
class ServerStats {
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

    ; The server's status, or "" when the server or the page can't be reached.
    static Fetch(url, timeout := 10) {
        try {
            return ServerStats.Parse(Json.Load(Http.Text(url, "application/json", timeout)))
        } catch as err {
            Logs.Warning("Could not read server status from " url ": " err.Message)
            return ""
        }
    }

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
