# SynSeeder

Fills up the **Syndicate | Competitive Server** in Hell Let Loose: Vietnam
while it's quiet, so real players want to join. This is called **seeding**.

## What happens

1. Each day at your chosen time, the app checks the server.
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

Tested on game v1.7, Steam and Epic, at 1920x1080, 2560x1440, 3840x2160,
2560x1080, 3440x1440 and 5120x2160.

## For developers

```
pip install -r requirements-dev.txt
python -m pytest
python -m seeder --seed      # run a seeding session now (Windows)
python -m seeder --record    # screenshot every 3s, for making templates
python tools/crop_templates.py <dir>   # re-cut templates after a game patch
python tools/make_assets.py  # redraw the window's images and the icon (needs Pillow)
build.bat                    # makes dist\SynSeeder.exe
```

Pushing a tag like `v1.0.1` publishes a release that installed copies pick
up. Set `__version__` in `seeder/__init__.py` to match first, or the build
fails. Settings live in `%APPDATA%\SynSeeder\config.json`, including
`leave_delay_minutes` and `auto_update`.
