# What's new in SynSeeder

The newest version is at the top. Each release on GitHub shows its own part
of this list.

<!--
Before tagging a version, add a "## 1.2.3" heading for it at the top, with a
few short, plain bullets saying what changed for the people using the app.
The build stops if the version in src/App.ahk has no part here.
Write each bullet on one line: the release page shows every line break.
-->

## 1.1.0

- **New: Seed when pinged.** When a Syngineer calls a seed with **/seed** on Discord, your PC can join in. It's off unless you tick it, and it only joins during the hours you pick, at most 3 times a day. If you're using the PC, it asks first.
- **The game no longer jumps in front of what you're doing.** It waits until nobody has used the PC for 5 minutes.
- **Safer updates from now on.** Before a new version takes over a run, it checks itself. If the check fails, your PC keeps the version it has.
- **Small fixes.** A mistake in the settings file can't break your runs, a slow stats page can't hold up **Ctrl+Alt+End**, and if saving fails when you press **Seed now**, the red message stays on screen.
- **Using Seed when pinged?** Delete your old SynSeeder.exe and open this new one. Pressing **Save** in an older copy turns Seed when pinged off.

## 1.0.2

- The little seedling at the top of the window has its stem back.

## 1.0.0

- The first release.
- Each day at the time you pick, it checks the server. Under 80 players? It opens the game, joins and makes its own squad.
- Works with the game on Steam and on Epic.
- At 80 players, it closes the game within 10 minutes.
- **Ctrl+Alt+End** stops a run at any time.
- It updates itself when a new version comes out.
