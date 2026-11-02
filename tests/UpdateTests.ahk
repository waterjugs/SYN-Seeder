; Updating from GitHub releases (ported from the first SynSeeder's tests/test_update.py).

; A stand-in SynSeeder.exe: "MZ" and ``size`` - 2 more bytes, the last one ``last``.
WriteExe(path, size := 1002, last := 0, head := 0x5A4D) {
    data := Buffer(size, 0)
    if size >= 2
        NumPut("UShort", head, data, 0)
    if size > 2
        NumPut("UChar", last, data, size - 1)
    file := FileOpen(path, "w")
    file.RawWrite(data, size)
    file.Close()
    return path
}

; The SHA-256 of the stand-in exe.
ExeSha() {
    path := WriteExe(App.Dir "\sha.tmp")
    sha := Sha256.File(path)
    FileDelete(path)
    return sha
}

; The parts of GitHub's latest-release answer that the updater reads.
ReleasePayload(tag := "v1.2.0", changes := "") {
    asset := Map("name", "SynSeeder.exe", "state", "uploaded", "size", 1002, "digest", "sha256:" ExeSha(),
        "browser_download_url", "https://github.com/waterjugs/SYN-Seeder/releases/download/" tag "/SynSeeder.exe")
    payload := Map("tag_name", tag, "draft", Json.Bool(false), "prerelease", Json.Bool(false),
        "assets", [Map("name", "notes.txt"), asset])
    if changes is Map
        for key, value in changes {
            if SubStr(key, 1, 6) = "asset." {
                if value = "<none>"
                    asset.Delete(SubStr(key, 7))
                else
                    asset[SubStr(key, 7)] := value
            } else {
                payload[key] := value
            }
        }
    return Json.Load(Json.Dump(payload))  ; as it comes back from GitHub
}

; A release build of v1.0.0 installed in App.Dir\bin; records what the updater does.
InstalledRelease() {
    folder := App.Dir "\bin"
    DirCreate(folder)
    exe := WriteExe(folder "\SynSeeder.exe")
    calls := []
    state := {calls: calls, starts: true, exe: exe, folder: folder, tag: "v1.2.0"}
    Patches.Value(App, "VERSION", "1.0.0")
    Patches.Set(Updater, "ReleaseBuild", (*) => true)
    Patches.Set(Updater, "Latest", (*) => (calls.Push("latest"), Updater.ParseRelease(ReleasePayload(state.tag))))
    download(this, release, dest, save := "") {
        SplitPath(dest, &name)
        calls.Push("download " release.tag " " name)
        WriteExe(dest)
        return true
    }
    Patches.Set(Updater, "Download", download)
    handOver(this, fresh, exe, tag, args, clock := "") {
        SplitPath(fresh, &name)
        calls.Push("hand over " name " " tag " " args)
        return state.starts
    }
    Patches.Set(Updater, "HandOver", handOver)
    return state
}

; The seeding lock and process starting, as HandOver uses them.
FakeLock(options := "") {
    lock := {events: [], checks: 0, polls: 0, takesLockAfter: "", exitsAfter: "", spawnError: "", freeAtEnd: true}
    if IsObject(options)
        for name, value in options.OwnProps()
            lock.%name% := value
    Patches.Set(SeedLock, "Release", (*) => lock.events.Push("release"))
    Patches.Set(SeedLock, "Claim", (*) => (lock.events.Push("claim"), lock.freeAtEnd))
    spawn(this, program, arguments) {
        SplitPath(program, &name)
        lock.events.Push("spawn " name " " arguments)
        if lock.spawnError
            throw OSError(lock.spawnError)
        return 4242
    }
    Patches.Set(SeedLock, "Spawn", spawn)
    alive(this, pid) {
        lock.polls++
        return lock.exitsAfter = "" || lock.polls <= lock.exitsAfter
    }
    Patches.Set(SeedLock, "Alive", alive)
    held(*) {
        lock.checks++
        return lock.takesLockAfter != "" && lock.checks > lock.takesLockAfter
    }
    Patches.Set(SeedLock, "HeldElsewhere", held)
    Patches.Set(SeedLock, "End", (this, pid) => lock.events.Push("end " pid))
    return lock
}

HandOverWith(lock, clock := "") {
    fresh := WriteExe(App.Dir "\" Updater.UPDATE_NAME)
    exe := App.Dir "\SynSeeder.exe"
    taken := Updater.HandOver(fresh, exe, "v1.2.0", "--seed --max-minutes 5", clock ? clock : FakeClock())
    return {taken: taken, fresh: fresh, exe: exe}
}

FilesIn(folder) {
    names := []
    loop files folder "\*"
        names.Push(A_LoopFileName)
    return names
}

class UpdateTests {
    static Test_parse_release_reads_the_exe_asset() {
        release := Updater.ParseRelease(ReleasePayload())
        AssertEq(release.tag, "v1.2.0")
        AssertEq(release.version, [1, 2, 0])
        Assert(SubStr(release.url, -21) == "/v1.2.0/SynSeeder.exe", release.url)
        AssertEq(release.size, 1002)
        AssertEq(release.sha256, ExeSha())
    }

    static Test_parse_release_without_a_checksum() {
        AssertEq(Updater.ParseRelease(ReleasePayload(, Map("asset.digest", "<none>"))).sha256, "")
    }

    static Test_parse_release_skips_what_it_cant_install() {
        for change in [Map("prerelease", Json.Bool(true)), Map("draft", Json.Bool(true)), Map("tag_name", "latest"),
            Map("assets", [Map("name", "notes.txt")])]
            AssertEq(Updater.ParseRelease(ReleasePayload(, change)), "", Json.Dump(change))
    }

    static Test_parse_release_skips_an_exe_still_uploading_or_not_https() {
        AssertEq(Updater.ParseRelease(ReleasePayload(, Map("asset.state", "starter"))), "")
        AssertEq(Updater.ParseRelease(ReleasePayload(, Map("asset.browser_download_url", "http://example.com/SynSeeder.exe"))), "")
    }

    static Test_latest_reads_github() {
        text := Json.Dump(ReleasePayload())
        AssertEq(Updater.Latest(, (url) => text).version, [1, 2, 0])
    }

    static Test_latest_is_empty_when_github_cant_be_reached() {
        fail(url) {
            throw OSError("no network")
        }
        AssertEq(Updater.Latest(, fail), "")
        AssertEq(Updater.Latest(, (url) => "<html>rate limited</html>"), "")
    }

    static Test_download_checks_and_keeps_a_good_file() {
        folder := App.Dir "\dl"
        DirCreate(folder)
        dest := folder "\" Updater.UPDATE_NAME
        Assert(Updater.Download(Updater.ParseRelease(ReleasePayload()), dest, (url, path) => WriteExe(path)))
        AssertEq(Sha256.File(dest), ExeSha())
        AssertEq(FilesIn(folder), [Updater.UPDATE_NAME])
    }

    static Test_download_throws_away_a_bad_file() {
        folder := App.Dir "\dl"
        DirCreate(folder)
        dest := folder "\" Updater.UPDATE_NAME
        cases := [
            [(url, path) => WriteExe(path, 1001), true],          ; cut short
            [(url, path) => WriteExe(path, 1001), false],         ; cut short, and GitHub gave no checksum
            [(url, path) => WriteExe(path, 1002, 0x78), true],    ; same size, different bytes
            [(url, path) => WriteExe(path, 1002, 0, 0x683C), true]]  ; not a program at all
        for item in cases {
            release := Updater.ParseRelease(item[2] ? ReleasePayload() : ReleasePayload(, Map("asset.digest", "<none>")))
            Assert(!Updater.Download(release, dest, item[1]), "case " A_Index)
            AssertEq(FilesIn(folder), [], "case " A_Index)
        }
    }

    static Test_download_survives_a_dropped_connection() {
        folder := App.Dir "\dl"
        DirCreate(folder)
        dropped(url, path) {
            WriteExe(path, 10)
            throw OSError("dropped")
        }
        Assert(!Updater.Download(Updater.ParseRelease(ReleasePayload()), folder "\" Updater.UPDATE_NAME, dropped))
        AssertEq(FilesIn(folder), [])
    }

    static Test_cleanup_removes_half_finished_files_only() {
        folder := App.Dir "\bin"
        DirCreate(folder)
        for name in ["SynSeeder.exe", "SynSeeder-update.exe", "SynSeeder-update.exe.part", "SynSeeder.exe.new"]
            WriteExe(folder "\" name)
        Updater.Cleanup(folder)
        AssertEq(FilesIn(folder), ["SynSeeder-update.exe", "SynSeeder.exe"])
    }

    static Test_downloaded_recognises_an_earlier_download() {
        path := App.Dir "\" Updater.UPDATE_NAME
        release := Updater.ParseRelease(ReleasePayload())
        Assert(!Updater.Downloaded(release, path))
        WriteExe(path)
        Assert(Updater.Downloaded(release, path))
        Assert(!Updater.Downloaded(Updater.ParseRelease(ReleasePayload(, Map("asset.digest", "<none>"))), path))  ; nothing to check it by
        WriteExe(path, 1002, 0x78)
        Assert(!Updater.Downloaded(release, path))
    }

    ; Deciding whether to update

    static Test_a_newer_release_takes_over() {
        state := InstalledRelease()
        Assert(Updater.UpdateAndHandOver(SeederConfig(), "--seed", state.exe))
        AssertEq(state.calls, ["latest", "download v1.2.0 SynSeeder-update.exe", "hand over SynSeeder-update.exe v1.2.0 --seed"])
    }

    static Test_same_or_older_release_does_nothing() {
        state := InstalledRelease()
        for version in ["1.2.0", "1.3.0"] {
            Patches.Value(App, "VERSION", version)
            state.calls.Length := 0
            Assert(!Updater.UpdateAndHandOver(SeederConfig(), "--seed", state.exe))
            AssertEq(state.calls, ["latest"], version)
        }
    }

    static Test_a_finished_update_is_cleared_away() {
        state := InstalledRelease()
        fresh := WriteExe(state.folder "\" Updater.UPDATE_NAME)
        Patches.Value(App, "VERSION", "1.2.0")
        Assert(!Updater.UpdateAndHandOver(SeederConfig(), "--seed", state.exe))
        Assert(!FileExist(fresh))
    }

    static Test_an_update_downloaded_earlier_is_used_again() {
        state := InstalledRelease()
        WriteExe(state.folder "\" Updater.UPDATE_NAME)
        Assert(Updater.UpdateAndHandOver(SeederConfig(), "--seed", state.exe))
        AssertEq(state.calls, ["latest", "hand over SynSeeder-update.exe v1.2.0 --seed"])
    }

    static Test_a_release_that_keeps_failing_to_start_is_skipped() {
        state := InstalledRelease()
        state.starts := false
        loop Updater.MAX_FAILURES
            Assert(!Updater.UpdateAndHandOver(SeederConfig(), "--seed", state.exe))
        AssertEq(Updater.Failures("v1.2.0"), Updater.MAX_FAILURES)
        state.calls.Length := 0
        Assert(!Updater.UpdateAndHandOver(SeederConfig(), "--seed", state.exe))
        AssertEq(state.calls, ["latest"])
        ; A newer release gets its own tries.
        state.tag := "v1.2.1"
        Assert(!Updater.UpdateAndHandOver(SeederConfig(), "--seed", state.exe))
        Assert(InStr(state.calls[state.calls.Length], "hand over") = 1)
        AssertEq(Updater.Failures("v1.2.1"), 1)
    }

    static Test_switched_off_in_settings() {
        state := InstalledRelease()
        config := SeederConfig()
        config.auto_update := false
        Assert(!Updater.UpdateAndHandOver(config, "--seed", state.exe))
        AssertEq(state.calls, [])
    }

    static Test_builds_that_arent_releases_never_update() {
        state := InstalledRelease()
        Patches.Set(Updater, "ReleaseBuild", (*) => false)
        Assert(!Updater.UpdateAndHandOver(SeederConfig(), "--seed", state.exe))
        AssertEq(state.calls, [])
    }

    static Test_running_as_a_script_is_not_a_release_build() {
        Assert(!Updater.ReleaseBuild())
        Assert(!Build.RELEASE)  ; CI sets it only for a release
    }

    ; Handing the run over to the new version

    static Test_hand_over_when_the_new_version_takes_the_lock() {
        lock := FakeLock({takesLockAfter: 3})
        result := HandOverWith(lock)
        Assert(result.taken)
        AssertEq(lock.events, ["release", "spawn SynSeeder-update.exe --install-to " QuoteArg(result.exe)
            . " --old-pid " DllCall("GetCurrentProcessId", "UInt") " --seed --max-minutes 5"])
        Assert(FileExist(result.fresh))  ; it's running; the next run deletes it
    }

    static Test_hand_over_falls_back_when_the_new_version_exits() {
        lock := FakeLock({exitsAfter: 2})
        result := HandOverWith(lock)
        Assert(!result.taken)
        AssertEq(lock.events[lock.events.Length], "claim")
        for event in lock.events
            Assert(InStr(event, "end") != 1, "ended a process that had exited")
        Assert(!FileExist(result.fresh))
    }

    static Test_hand_over_gives_up_on_a_new_version_that_hangs() {
        lock := FakeLock()
        clock := FakeClock()
        result := HandOverWith(lock, clock)
        Assert(!result.taken)
        Assert(clock.at >= Updater.HANDOVER_SECONDS)
        AssertEq(Slice(lock.events, lock.events.Length - 1), ["end 4242", "claim"])
    }

    static Test_hand_over_falls_back_when_the_new_version_cant_start() {
        lock := FakeLock({spawnError: "blocked by antivirus"})
        result := HandOverWith(lock)
        Assert(!result.taken)
        AssertEq(lock.events[lock.events.Length], "claim")
        Assert(!FileExist(result.fresh))
    }

    static Test_hand_over_starts_nothing_when_asked_to_stop_first() {
        lock := FakeLock({takesLockAfter: 0})
        result := HandOverWith(lock, StoppingClock(0))
        AssertEq(result.taken, Updater.STOPPED)
        AssertEq(lock.events, [])  ; kept the lock
        Assert(FileExist(result.fresh))
    }

    static Test_hand_over_ends_the_new_version_when_asked_to_stop() {
        lock := FakeLock()  ; never takes the lock
        result := HandOverWith(lock, StoppingClock(3))
        AssertEq(result.taken, Updater.STOPPED)
        AssertEq(Slice(lock.events, lock.events.Length - 1), ["end 4242", "claim"])
        Assert(FileExist(result.fresh))  ; still good for the next run
    }

    static Test_a_stopped_hand_over_isnt_a_failed_release() {
        state := InstalledRelease()
        state.starts := Updater.STOPPED
        Assert(!Updater.UpdateAndHandOver(SeederConfig(), "--seed", state.exe))
        AssertEq(Updater.Failures("v1.2.0"), 0)
    }

    static Test_hand_over_yields_to_another_run_that_holds_the_lock() {
        lock := FakeLock({exitsAfter: 0, freeAtEnd: false})
        Assert(HandOverWith(lock).taken)
    }

    ; The new version installing itself

    static Test_install_copies_itself_over_the_old_exe() {
        folder := App.Dir "\bin"
        DirCreate(folder)
        target := WriteExe(folder "\SynSeeder.exe")
        source := WriteExe(App.Dir "\" Updater.UPDATE_NAME, 1002, 0x42)
        Assert(Updater.Install(target, [], source))
        AssertEq(Sha256.File(target), Sha256.File(source))
        AssertEq(FilesIn(folder), ["SynSeeder.exe"])
    }

    static Test_install_waits_while_the_old_exe_is_in_use() {
        folder := App.Dir "\bin"
        DirCreate(folder)
        target := WriteExe(folder "\SynSeeder.exe")
        source := WriteExe(App.Dir "\" Updater.UPDATE_NAME, 1002, 0x42)
        Patches.Value(Updater, "REPLACE_TRIES", 2)
        hold := FileOpen(target, "r -rwd")  ; e.g. a SynSeeder window started from it
        try
            Assert(!Updater.Install(target, [], source))
        finally
            hold.Close()
        SetTimer(Updater.retrying, 0)  ; the background retry isn't part of this test
        AssertEq(FilesIn(folder), ["SynSeeder.exe", "SynSeeder.exe.new"])  ; kept for the retries
        Assert(Updater.Replace(target ".new", target, 1, 0))
        AssertEq(Sha256.File(target), Sha256.File(source))
    }

    static Test_install_gives_up_if_it_cant_copy_itself() {
        folder := App.Dir "\bin"
        DirCreate(folder)
        target := WriteExe(folder "\SynSeeder.exe")
        Assert(!Updater.Install(target, [], App.Dir "\missing.exe"))
        AssertEq(FilesIn(folder), ["SynSeeder.exe"])
    }

    static Test_newer_installed_copy_is_left_alone() {
        Assert(!DailyTask.NewerInstalled(App.Dir "\missing.exe"))
        Assert(!DailyTask.NewerInstalled(WriteExe(App.Dir "\plain.exe")))  ; no version details
    }
}
