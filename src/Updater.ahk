; Keeping SynSeeder up to date from its GitHub releases.
;
; Only official release builds update themselves: CI sets Build.RELEASE in
; src\Build.ahk when it builds a v* tag, so a test build stays the version it
; is. Before each seeding run, a release build asks GitHub for the latest
; release and, if that's newer, downloads its SynSeeder.exe next to itself as
; SynSeeder-update.exe.
;
; A running exe can't be overwritten, so the new version finishes the job.
; The old one lets go of the seeding lock and starts
; ``SynSeeder-update.exe --install-to <old exe> --old-pid <pid> --seed``; once
; the new one has the lock, the old one exits. The new one waits for the old
; process to end, copies itself over the old file and carries on with the
; run. If something else still has the file open, such as a SynSeeder window
; started from it, the new one keeps trying during the run, and keeps
; SynSeeder-update.exe so the next run can hand over again without
; downloading it again.
;
; A release that fails to start three times is skipped until a newer one is
; out, so a bad release can't hold up every run.

class Updater {
    static LATEST_RELEASE := "https://api.github.com/repos/waterjugs/SYN-Seeder/releases/latest"
    static ASSET_NAME := "SynSeeder.exe"
    static UPDATE_NAME := "SynSeeder-update.exe"
    static FAILURES_NAME := "update-failed.json"  ; in App.Dir: the release that last failed to start, and how often
    static MAX_FAILURES := 3
    static HANDOVER_SECONDS := 120  ; for the new version to start; antivirus can take a while over a new exe
    static EXIT_SECONDS := 60       ; for the old version to exit once the new one has the lock
    static REPLACE_TRIES := 5       ; a second apart, once the old version has exited
    static RETRY_SECONDS := 30      ; between tries in the background after that
    static retrying := ""           ; the background retry, while there is one

    ; True in an exe CI built from a v* tag; only those update themselves.
    static ReleaseBuild() => A_IsCompiled && Build.RELEASE

    ; The release's SynSeeder.exe as {tag, version, url, size, sha256}, or ""
    ; if it has none or isn't a final release.
    static ParseRelease(payload) {
        field(obj, key, default := "") => obj is Map && obj.Has(key) ? obj[key] : default
        if !(payload is Map) || field(payload, "draft") || field(payload, "prerelease")
            return ""
        tag := field(payload, "tag_name")
        tag := IsObject(tag) ? "" : String(tag)
        version := App.ParseVersion(tag)
        asset := ""
        assets := field(payload, "assets")
        if assets is Array {
            for item in assets {
                if field(item, "name") == Updater.ASSET_NAME && field(item, "state", "uploaded") == "uploaded" {
                    asset := item
                    break
                }
            }
        }
        if version = "" || asset = ""
            return ""
        url := field(asset, "browser_download_url")
        if IsObject(url) || SubStr(url, 1, 8) !== "https://"
            return ""
        digest := field(asset, "digest")
        digest := IsObject(digest) ? "" : String(digest)
        size := field(asset, "size", 0)
        return {tag: tag, version: version, url: url, size: IsInteger(size) ? Integer(size) : 0,
            sha256: SubStr(digest, 1, 7) == "sha256:" ? StrLower(SubStr(digest, 8)) : ""}
    }

    ; The latest release, or "" if GitHub can't be reached or the release has
    ; no exe. ``getText`` fetches a URL's text (tests pass their own).
    static Latest(url := "", getText := "") {
        url := url != "" ? url : Updater.LATEST_RELEASE
        try {
            text := getText ? getText(url) : Http.Text(url, "application/vnd.github+json", 15)
            return Updater.ParseRelease(Json.Load(text))
        } catch as err {  ; network, HTTP or payload errors all mean "no update today"
            Logs.Warning("Couldn't check for updates: " err.Message)
            return ""
        }
    }

    ; Downloads the release's exe to ``dest`` and checks it. False, leaving no
    ; file, if anything is off. ``save`` downloads a URL to a file (tests pass their own).
    static Download(release, dest, save := "") {
        part := dest ".part"
        try {
            ; An exe is only ever run after it's been checked against GitHub's
            ; own checksum of the file, so without one it isn't even fetched.
            if release.sha256 = ""
                throw Error("GitHub gave no checksum to check it by")
            if save
                save(release.url, part)
            else
                Http.Download(release.url, part, "application/octet-stream", 30)
            size := FileGetSize(part)
            head := ""
            if size >= 2 {
                file := FileOpen(part, "r")
                head := file.ReadUShort()
                file.Close()
            }
            if head != 0x5A4D  ; "MZ"
                throw Error("it isn't a Windows program")
            if release.size && size != release.size
                throw Error("got " size " bytes, expected " release.size)
            if Sha256.File(part) != release.sha256
                throw Error("its checksum doesn't match")
            FileMove(part, dest, true)
            return true
        } catch as err {
            Logs.Warning("Couldn't download " release.tag ": " err.Message)
            try FileDelete(part)
            return false
        }
    }

    ; True if an earlier run already downloaded this release's exe to ``path``.
    static Downloaded(release, path) => release.sha256 != "" && Sha256.File(path) == release.sha256

    ; Deletes half-finished downloads and installs an earlier run left next to the exe.
    static Cleanup(folder) {
        for name in [Updater.UPDATE_NAME ".part", Updater.ASSET_NAME ".new"]
            try FileDelete(folder "\" name)
    }

    ; How many times this release has failed to start.
    static Failures(tag) {
        try {
            record := Json.Load(FileRead(App.Dir "\" Updater.FAILURES_NAME, "UTF-8"))
            return record["tag"] == tag ? Integer(record["failures"]) : 0
        }
        return 0
    }

    static RecordFailure(tag) {
        count := Updater.Failures(tag) + 1
        try FileOpen(App.Dir "\" Updater.FAILURES_NAME, "w", "UTF-8-RAW").Write(Json.Dump(Map("tag", tag, "failures", count), "", ["tag", "failures"]))
    }

    ; Before a run: if a newer release is out, downloads it and lets it take over.
    ;
    ; True means the new version has taken over the run and this process
    ; should exit without seeding; false means carry on with this version (or
    ; stop, if ``shouldStop`` says so: a run asked to stop doesn't hand over).
    ; ``args`` are this run's arguments, passed on to the new version; ``exe``
    ; is the program being updated (this one unless a test says otherwise).
    static UpdateAndHandOver(config, args, exe := "", shouldStop := "") {
        if !Updater.ReleaseBuild()
            return false
        exe := exe != "" ? exe : A_ScriptFullPath
        SplitPath(exe, , &folder)
        fresh := folder "\" Updater.UPDATE_NAME
        Updater.Cleanup(folder)
        release := config.auto_update ? Updater.Latest() : ""
        if !release || App.CompareVersions(release.version, App.ParseVersion(App.VERSION)) <= 0 {
            try FileDelete(fresh)
            return false
        }
        if Updater.Failures(release.tag) >= Updater.MAX_FAILURES {
            Logs.Warning("Skipping " release.tag ": it failed to start " Updater.MAX_FAILURES " times. "
                . "A newer release will be tried.")
            try FileDelete(fresh)
            return false
        }
        Logs.Info("Updating from v" App.VERSION " to " release.tag)
        if !(Updater.Downloaded(release, fresh) || Updater.Download(release, fresh))
            return false
        result := Updater.HandOver(fresh, exe, release.tag, args, SeedClock(shouldStop))
        if result == true
            return true
        if result != Updater.STOPPED
            Updater.RecordFailure(release.tag)
        return false
    }

    static STOPPED := "stopped"

    ; Starts the new exe to install itself over ``exe`` and take over this run.
    ;
    ; True once it has taken the seeding lock. False if it didn't start; then
    ; this process has the lock back and carries on as it is. STOPPED if the
    ; run was asked to stop (``clock`` says when): then nothing is started, or
    ; what was started is ended, and this process has the lock back.
    static HandOver(fresh, exe, tag, args, clock := "") {
        clock := clock ? clock : SeedClock()
        Sleep(-1)  ; take in a stop asked for while the update was downloading
        try {
            clock.Check()
        } catch SeedStopped {
            return Updater.STOPPED
        }
        old := DllCall("GetCurrentProcessId", "UInt")
        SeedLock.Release()
        pid := 0, stopped := false
        try {
            pid := SeedLock.Spawn(fresh, "--install-to " QuoteArg(exe) " --old-pid " old (args != "" ? " " args : ""))
            deadline := clock.Now() + Updater.HANDOVER_SECONDS
            while clock.Now() < deadline && SeedLock.Alive(pid) {
                if SeedLock.HeldElsewhere() {
                    Logs.Info(tag " has taken over this run")
                    return true
                }
                clock.Sleep(0.5)
            }
            Logs.Warning(tag " didn't start; carrying on with v" App.VERSION)
        } catch SeedStopped {
            stopped := true  ; the new version hasn't taken over yet, so it's ended below
        } catch as err {  ; whatever happens, this process must get the lock back
            Logs.Warning("Couldn't start " tag ": " err.Message)
        }
        if pid && SeedLock.Alive(pid)
            SeedLock.End(pid)
        if !stopped  ; a stopped handover's download is fine for the next run
            try FileDelete(fresh)
        if !SeedLock.Claim() {
            Logs.Info("Another seeding run started meanwhile; leaving it to that one")
            return true
        }
        return stopped ? Updater.STOPPED : false
    }

    ; Run by the new version that HandOver() started: copies this exe over ``target``.
    ;
    ; Waits for the old version's process to end, since Windows won't replace
    ; a running exe. If something else still has the file open, it returns
    ; false and keeps trying in the background for the rest of the run; a
    ; later run hands over again if this one never managed.
    static Install(target, oldPids, source := "") {
        temp := target ".new"
        try {
            FileCopy(source != "" ? source : A_ScriptFullPath, temp, true)
        } catch as err {
            Logs.Warning("Couldn't copy the update into place: " err.Message)
            try FileDelete(temp)
            return false
        }
        deadline := A_TickCount + Updater.EXIT_SECONDS * 1000
        for pid in oldPids
            ProcessWaitClose(pid, Max(0, deadline - A_TickCount) / 1000)
        if Updater.Replace(temp, target, Updater.REPLACE_TRIES, 1)
            return true
        Logs.Warning("Couldn't replace " target " yet; something has it open, maybe a SynSeeder window "
            . "started from it. Trying again every " Updater.RETRY_SECONDS " s during this run.")
        retry() {
            if !FileExist(temp) || Updater.Replace(temp, target, 1, 0)  ; installed, or nothing left to install
                SetTimer(retry, 0)
        }
        Updater.retrying := retry
        SetTimer(retry, Updater.RETRY_SECONDS * 1000)
        return false
    }

    ; Moves ``temp`` over ``target``, trying ``tries`` times ``wait`` seconds apart.
    static Replace(temp, target, tries, wait) {
        loop tries {
            try {
                ReplaceFile(temp, target)
                Logs.Info("Installed v" App.VERSION)
                return true
            } catch as err {
                if A_Index >= tries {
                    Logs.Info("Couldn't replace " target ": " err.Message)
                    return false
                }
                Sleep(Round(wait * 1000))
            }
        }
        return false
    }
}
