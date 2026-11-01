# Trial builds

Every PyInstaller build of SynSeeder gets flagged by at least one antivirus
engine on VirusTotal. These are small native trial versions, built to see
which way of making the exe scans clean before rewriting the app in it.

- `cs/` is C# on .NET Framework 4.8, which Windows 10 and 11 already have.
- `ahk/` is AutoHotkey v2, like the old seeder that scans clean.

The variants:

| Variant | What's in it |
|---|---|
| full | Every part the real app needs: the window, clicks and key presses, finding buttons on screen, the player count, the daily task, and the self-update |
| noupdate | The same, but checking for updates only opens the release page |
| bare | Only a window, as a baseline |

Results so far (VirusTotal, unsigned, 64-bit):

- Round 1: every AutoHotkey 2.0.31 trial got one flag (Gridinsoft), even
  `bare`. C#: `bare` 1/71 (SecureAge APEX), `noupdate` 3/71.
- The old seeder that scans clean turned out to be built on AutoHotkey 2.0.18,
  with AutoHotkey's own icon and version details.
- Round 2 built `bare` and `full` on 2.0.18 and 2.0.31, each with SynSeeder's
  icon and version details (no suffix), only the icon (`-icon`), only the
  version details (`-version`) or neither (`-plain`). On 2.0.18 every `bare`
  build scanned 0/71 and every `full` build 1/71 (SecureAge APEX). On 2.0.31,
  the icon drew Gridinsoft, and the `full` builds also drew Microsoft's
  machine-learning engine. The plain AutoHotkey64.exe of both versions and the
  old seeder all scanned 0/71.
- Round 3 (2.0.18, all with the icon and version details) checks whether the
  last flag comes from the built-in button images or the code: `full-noimg`
  has no images, `bare-img` is the bare window plus the images, `full-bmp`
  stores them as uncompressed BMP files, and `noupdate` drops the self-update.

The images are built in by `images.ahk` (PNG), `images-bmp.ahk` (BMP copies
the workflow makes in `build/bmp`) or `images-none.ahk`.

Pushing to a `trial/` branch runs `.github/workflows/trial-builds.yml`. It
builds the trials, self-tests them, and scans each exe on VirusTotal with
`tools/vt_scan.py`. That needs a VirusTotal API key in the repository secret
`VT_API_KEY`. The results show as notes on the run and in its summary.
