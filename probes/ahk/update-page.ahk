; Update check for the "noupdate" trial: only opens the release page.

HandleUpdateArgs() => false

CheckForUpdates(*) {
    tag := LatestTag()
    if tag = "none published" || VerCompare(LTrim(tag, "v"), APP_VERSION) <= 0 {
        UI.Status.Value := "You have the latest version."
        return
    }
    UI.Status.Value := tag " is out. Download it from the page that just opened."
    Run RELEASE_PAGE
}
