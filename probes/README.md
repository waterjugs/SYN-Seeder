# Trial builds

Every PyInstaller build of SynSeeder gets flagged by at least one antivirus
engine on VirusTotal. These are small native trial versions, built to see
which way of making the exe scans clean before rewriting the app in it.

- `cs/` is C# on .NET Framework 4.8, which Windows 10 and 11 already have.
- `ahk/` is AutoHotkey v2, like the old seeder that scans clean.

Each comes in three variants:

| Variant | What's in it |
|---|---|
| full | Every part the real app needs: the window, clicks and key presses, finding buttons on screen, the player count, the daily task, and the self-update |
| noupdate | The same, but checking for updates only opens the release page |
| bare | Only a window, as a baseline |

Pushing to a `trial/` branch runs `.github/workflows/trial-builds.yml`. It
builds all six, self-tests them, and scans each exe on VirusTotal with
`tools/vt_scan.py`. That needs a VirusTotal API key in the repository secret
`VT_API_KEY`. The results show as notes on the run and in its summary.
