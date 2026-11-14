# SynSeeder

Fills up the **Syndicate | Competitive Server** in Hell Let Loose: Vietnam
while it's quiet, so real players want to join. This is called **seeding**.

## What happens

1. Each day at your chosen time, the app checks the server. It can also do
   this when someone calls a seed on Discord (see **Seed when pinged**).
2. Under 80 players? The game opens and joins Syndicate.
3. Then it makes its own squad on the team with fewer players.
4. Once the server hits 80, the game closes after a short random wait (up
   to 10 minutes), so seeders don't all leave together.

## First time only

- Finish the **Getting Started** and **Squad Leader** tutorials in the game.
- Set the game's display mode to **Borderless** or **Windowed**.

## Setup

1. Download `SynSeeder.exe` from the
   [latest release](https://github.com/waterjugs/SYN-Seeder/releases/latest).
2. Open it. If Windows warns you, click **More info**, then **Run anyway**.
3. Choose a time, and Steam or Epic.
4. Tick **Seed automatically**, then press **Save**.

Done! To try it now, press **Seed now**.

## Seed when pinged

Syngineers can call a seed with **/seed** in the SYNDICATE Discord. Want your
PC to join in? Tick **Seed when pinged**, pick your hours, and press **Save**.

- Nobody at the PC for 5 minutes? The run starts by itself.
- In use, or something full screen? It asks you first.
- It starts at most 3 runs a day, never two within 30 minutes.

## Good to know

- Leave the PC on, signed in and unlocked.
- **Ctrl+Alt+End** stops a run.
- Already playing? Nothing happens.
- Updates install themselves.
- Stuck? Send us `%APPDATA%\SynSeeder\seeder.log` and the `debug` folder
  privately ([how](PRIVACY.md#sending-your-log-or-screenshots-to-someone)).

## Rules

Using SynSeeder means agreeing to the [Terms of Service](TERMS.md). Steam's
rules don't allow bots, so any risk to your account is yours. See the
[Privacy Policy](PRIVACY.md) for what's stored and sent.

Made for game v1.7 on Steam and Epic. Its button finder is tested on
screenshots at 1920x1080, 2560x1440, 3840x2160, 2560x1080, 3440x1440 and
5120x2160. On a narrower screen like 1920x1200, if it can't find the
buttons, run the game in a 1920x1080 window.

## For developers

SynSeeder is an [AutoHotkey](https://www.autohotkey.com/) v2.0.18 script.

```
AutoHotkey64.exe SynSeeder.ahk             # the window (--seed seeds now)
AutoHotkey64.exe SynSeeder.ahk --record    # screenshots, for making button images
AutoHotkey64.exe SynSeeder.ahk --check-seed-calls   # one Seed when pinged check
AutoHotkey64.exe SynSeeder.ahk --check     # the start-up check an update must pass
AutoHotkey64.exe /ErrorStdOut tests\run_tests.ahk
python tests/make_fixtures.py build/fixtures   # needs opencv-python-headless
AutoHotkey64.exe /ErrorStdOut tests\vision_cases.ahk build\fixtures
python tools/crop_templates.py <dir>       # re-cut button images after a game patch
```

GitHub builds and tests every push. A tag like `v1.1.1` makes a draft
release and scans its exe on VirusTotal; installed copies update only once
it's published. Bump the version in `src/App.ahk` and `SynSeeder.ahk` first,
and say what changed in [CHANGELOG.md](CHANGELOG.md): the release shows it.
The exe downloads its button images and fonts from this repository and
checks them against `src/ButtonFiles.ahk` and `src/FontFiles.ahk`. Settings
live in `%APPDATA%\SynSeeder\config.json`.
