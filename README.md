# SynSeeder

SynSeeder helps fill up the **Syndicate | Competitive Server** in
Hell Let Loose: Vietnam.

Nobody likes joining an empty server. So when the server is quiet,
SynSeeder plays for you. The server looks busy, and real players join.
This is called **seeding**.

## How it works

1. At the time you pick, SynSeeder wakes up.
2. It checks how many people are on the server.
3. If 80 or more are playing, the server is full enough. It goes back
   to sleep.
4. If fewer than 80 are playing, it opens the game for you.
5. It finds the Syndicate server and joins it.
6. It picks the team with fewer players.
7. It makes its own squad. It never joins someone else's squad.
8. It jumps in and stays. Now and then it takes a tiny step, so the game
   doesn't kick it for standing still.
9. When the server has 80 players, it waits a little (0 to 10 minutes),
   then closes the game.

**Why wait?** If every SynSeeder left at the same moment, the server
would drop under 80 again. Each one waits a different amount of time, so
they leave one by one. If the server drops under 80 while it waits, it
stays and keeps seeding.

## Before you start (only once)

- Open the game yourself and finish two tutorials: **Getting Started**
  and **Squad Leader**. The game won't let you make a squad until you
  do. If you have the game on Steam and Epic, do them on the one you'll
  seed with.
- In the game's settings, set the display mode to **Borderless** (also
  called Windowed Fullscreen) or **Windowed**. Then SynSeeder can see
  the game.

## Set it up

1. Download `SynSeeder.exe` from the
   [latest release](https://github.com/waterjugs/SYN-Seeder/releases/latest).
2. Double-click it. If Windows says "Windows protected your PC", click
   **More info**, then **Run anyway**.
3. Pick the time to seed each day.
4. Pick **Steam** or **Epic**.
5. Tick **Seed automatically** and press **Save**.

That's it! Now it seeds by itself every day at that time.

Want to try it now? Press **Seed now**.

## Good to know

- At seeding time, your PC must be on, signed in and unlocked. If it was
  asleep, SynSeeder runs when the PC wakes up.
- To stop a run, press **Ctrl+Alt+End**, or **Stop seeding** in the
  window. The game closes.
- If you're already playing the game, SynSeeder leaves you alone.
- It only presses keys when the game is in front. If you click on
  something else, it waits until you stop using the mouse and keyboard
  for 15 seconds, then brings the game back.
- It always stops after 4 hours.
- It updates itself. Before each run it checks for a newer version.
- It keeps a copy of itself in `%LOCALAPPDATA%\SynSeeder` and adds a
  Windows task called *SynSeeder* that starts it each day.
- To stop seeding every day, untick **Seed automatically** and press
  **Save**.

## If it gets stuck

If SynSeeder gets stuck (for example after a game update), it saves a
picture of the screen. The pictures are in `%APPDATA%\SynSeeder\debug`
and its notes are in `%APPDATA%\SynSeeder\seeder.log`. Send both to us
privately so we can fix it. The
[Privacy Policy](PRIVACY.md#sending-your-log-or-screenshots-to-someone)
says how.

## The rules

Using SynSeeder means you agree to the [Terms of Service](TERMS.md). The
short version: it comes as it is, and Steam's rules don't allow bots, so
any risk to your game account is yours. The [Privacy Policy](PRIVACY.md)
says what SynSeeder keeps on your PC and what it talks to: the server's
player count page and GitHub, nothing else.

## Tested on

Game version v1.7 (October and November 2026), on Steam and Epic, at
these screen sizes: 1920x1080, 2560x1440, 3840x2160 (4K), and the wide
screens 2560x1080, 3440x1440 and 5120x2160.

## For developers

SynSeeder finds buttons by matching pictures of them (in `templates/`),
not by clicking fixed spots, so it works at any screen size. Settings are
in `%APPDATA%\SynSeeder\config.json`. Two you might change by hand:
`"leave_delay_minutes"` (the longest wait before leaving, default 10;
0 leaves straight away) and `"auto_update"` (`false` turns updates off).

```
pip install -r requirements-dev.txt
python -m pytest
python -m seeder --seed      # run a seeding session now (Windows)
python -m seeder --record    # screenshot every 3s, for making templates
python tools/crop_templates.py <dir>   # re-cut templates after a game patch
python tools/make_assets.py  # redraw the window's images and the icon (needs Pillow)
build.bat                    # makes dist\SynSeeder.exe from SynSeeder.spec
```

GitHub Actions runs the tests and builds `SynSeeder.exe` on every push.
Pushing a tag like `v1.0.1` also publishes a release with the exe
attached, and every installed copy picks it up at its next run. Only exes
from a release update themselves, never one you built yourself. Set
`__version__` in `seeder/__init__.py` to the same number first: the build
fails if the tag and the version don't match.
