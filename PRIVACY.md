# SynSeeder Privacy Policy

Last updated: 14 November 2026

**New in version 1.1.0:** an optional **Seed when pinged** setting and a SynSeeder bot for Discord. The parts of this policy about the bot apply as soon as it's added to the SYNDICATE Discord server, and the parts about Seed when pinged apply only from version 1.1.0 on.

**Changed on 14 November 2026:** there's no 14-day wait any more. When the app, the seed-call service or the bot will collect, keep or send something new, we'll update this policy by the time the change happens.

SynSeeder doesn't send us your name, your files or anything you type, and it doesn't sell your information. It has no accounts, ads, analytics or crash reporting, and it never uploads your files. Like anything that goes online, it shows your IP address to the sites it talks to: the server's stats page, for the player count, and GitHub, to download the pictures and fonts SynSeeder uses and to check for and download updates. If you tick **Seed when pinged**, it also checks about once a minute whether someone has called a seed on Discord. It asks a small service that we run on Cloudflare, which sees your IP address and the time, like any website. We keep no record of them, though Cloudflare may keep its own for a while (see [What goes over the internet](#what-goes-over-the-internet)). If you use **/seed** on Discord, our bot gets your Discord ID, names and roles from Discord. It uses them on the spot to check you may call a seed and keeps no copy. Its reply in the channel doesn't name you, but Discord shows who used /seed above it, as it does for any command. Everything SynSeeder saves (settings, a log and the occasional screenshot) stays in folders on your own PC until you delete it.

This policy covers the SynSeeder app (SynSeeder.exe), its seed-call service and the SynSeeder bot on Discord, all made by the GitHub user waterjugs ("we", "us"). It doesn't cover Hell Let Loose: Vietnam, Steam, Epic, GitHub, Cloudflare, Discord, or the game server and its stats page. Other people run those, under their own rules and their own privacy policies where they have them.

## What SynSeeder keeps on your PC

SynSeeder saves only the items below, all on your PC, and none of them is sent anywhere.

| What | Where | What's in it | Kept until |
| --- | --- | --- | --- |
| Settings | `%APPDATA%\SynSeeder\config.json` | Your daily start time, Steam or Epic, and the seeding settings (server name, stats address, timings, updates on or off, and whether Seed when pinged is on, with its hours). Nothing about you. | You delete it |
| Log | `%APPDATA%\SynSeeder\seeder.log`, and `seeder.old.log` next to it | Times, player counts, each step of a run and any errors, which together show when your PC was on and in use. With Seed when pinged on, it also notes each seed call the PC saw and whether it started a run, skipped it or asked you first. It can include your Windows user name (inside folder paths) and the name of a program that was in front of the game. | You delete it. Once the log passes 5 MB, SynSeeder renames it `seeder.old.log` (replacing the older one) and starts a new one, so there are never more than two |
| Stuck screenshots | `%APPDATA%\SynSeeder\debug\` | A full-colour picture of the area where the game is drawn (or of your whole main screen, if it can't find the game window), saved when a run seems stuck while joining. It shows whatever is there, which can include player names, chat and any window or notification on top of the game. | The newest 20 are kept. Each time a new one is saved, older ones are deleted, so don't keep your own pictures in that folder |
| Recorded screenshots | `%APPDATA%\SynSeeder\screenshots\` | Only if you start the app with `--record`, a developer option for making button images: your whole main screen every 3 seconds, for 10 minutes by default (about 200 pictures). | You delete them |
| A copy of the app | `%LOCALAPPDATA%\SynSeeder\SynSeeder.exe` | Made when you press Seed now, or Save with Seed automatically or Seed when pinged ticked, so the scheduled tasks keep working if you move or delete your download. Newer versions from GitHub replace it. | You delete it |
| An update being installed | `%LOCALAPPDATA%\SynSeeder\SynSeeder-update.exe` | A newer version downloaded from GitHub. It copies itself over the app above and finishes that run. If something still has the app open, such as a SynSeeder window or a seed-call check started from it, the download stays here so a later run can finish installing it without downloading it again. While it downloads and copies itself into place, SynSeeder-update.exe.part and SynSeeder.exe.new can also appear here for a short time. | The first run after the update is in place deletes it |
| Button pictures and fonts | `%LOCALAPPDATA%\SynSeeder\buttons\` and `%LOCALAPPDATA%\SynSeeder\fonts\` | Pictures of the game's buttons, which SynSeeder looks for on screen, and the two fonts its window uses (Inter and Barlow Condensed). They're downloaded from GitHub the first time they're needed, and used only if they match fingerprints built into the app. The fonts are only for SynSeeder's own window and aren't installed in Windows. Nothing about you. While a file downloads, a copy ending in `.part` can appear for a short time. If the fonts can't be downloaded, a small `download-failed.txt` in the fonts folder notes when, so the window waits a few hours before trying again. | You delete them |
| Note of a failed update | `%APPDATA%\SynSeeder\update-failed.json` | Only if a new version fails its start-up check or fails to start: its version number and how many times it failed. After three failures SynSeeder skips that version and waits for the next one. | You delete it |
| Note of seed calls | `%APPDATA%\SynSeeder\seed-calls.json` | Only with Seed when pinged on: the random number of the last seed call this PC acted on, when it last started a seed-call run, how many it started today and, if a check failed, when to try again. This is so it never acts on the same call twice or too often. | You delete it |
| Scheduled task named SynSeeder | Windows Task Scheduler | Starts a run at your chosen time each day, under your Windows account and without admin rights. Windows stores your account name with the task. | You untick Seed automatically and press Save or Seed now |
| Scheduled task named SynSeeder seed calls | Windows Task Scheduler | Only with Seed when pinged on: a quick check about once a minute while you're signed in, under your Windows account and without admin rights. Outside your hours, or if the PC is locked, the game is open or a run is going, it closes at once without going online. Windows stores your account name with the task. | You untick Seed when pinged and press Save or Seed now |

On a work or school PC with a roaming profile, Windows may copy the `%APPDATA%` folder to your organisation's servers.

## What it looks at while it runs

To play the game, SynSeeder reads a few things on your PC as it goes. It uses them on the spot and doesn't save or send them, apart from the log lines and stuck screenshots listed above.

- **The game's picture.** Every couple of seconds while joining, and about every 30 seconds once in, it captures the area where the game is drawn (or your whole main screen, if it can't find the game window) and compares it with pictures of the game's buttons. It keeps only a grey, shrunk copy of each capture in memory, until the next capture replaces it.
- **Running programs.** It reads the names of running programs to find the game, and looks for SynSeeder's own hidden windows to find other SynSeeder runs (so it never runs twice and Stop seeding works). When another window keeps the game from coming to the front, it notes that program's name in the log.
- **How long since you last used the mouse or keyboard.** Windows reports only the time of the last input, never what you typed or clicked. SynSeeder uses it to wait until you've left the PC alone before bringing the game to the front: 5 minutes while another program's window is in front, or 10 seconds while none is (15 seconds in every case before version 1.1.0). It also waits until you've left it alone for 10 seconds before it carries on when the game comes back to the front some other way, such as when you click it. With Seed when pinged on, it also uses it to start a seed-call run on its own only if you haven't touched the mouse or keyboard for 5 minutes.
- **Whether something is full screen,** only with Seed when pinged on. Windows says only whether a full-screen program or a presentation is on, not which program. If one is, SynSeeder asks you before a seed call starts the game.
- **The Ctrl+Alt+End shortcut.** It registers this one shortcut to stop a run. Windows tells it only when that exact shortcut is pressed; it doesn't see any other keys.
- **Your keyboard layout,** so it presses the right keys on any layout.
- **Whether the PC is locked,** because it can't play on a locked screen.
- **Epic's list of installed games,** only if you choose Epic, to find Hell Let Loose: Vietnam's entry so it can start it.

Apart from what's listed here, SynSeeder doesn't open your files, browser, messages, contacts or accounts, and it doesn't record your keystrokes. A screen capture can still catch a message or notification that pops up over the game.

## What goes over the internet

SynSeeder itself makes only the requests below. None of them includes anything about you beyond your IP address, the time, and that you use SynSeeder (GitHub can also tell which version you have from the files you download).

| Request | When | Goes to | What the receiver sees |
| --- | --- | --- | --- |
| The server's player count | When the window opens and every 30 seconds while it's open, at the start of each run, and about every 30 seconds while seeding | The server's public stats page, `syn-stats-nam.radicalgamingstats.com`, through Cloudflare | Your IP address, the time, and that the request came from "SynSeeder" |
| Pictures of the game's buttons, and the window's fonts | The first time they're needed, and again only if one goes missing or doesn't match | GitHub (`raw.githubusercontent.com`) | Your IP address, the time, and which of SynSeeder's files you're getting, for which version |
| Is there a newer version? | At the start of each run | GitHub (`api.github.com`) | Your IP address, the time, and that the request came from "SynSeeder" |
| Downloading the newer version | Only when there is one | GitHub | Your IP address, the time, and which version you're getting |
| Has a seed been called? | Only with Seed when pinged on: about once a minute while you're signed in and inside your hours, and only while the PC is unlocked, the game is closed and no run is going | SynSeeder's seed-call service, which we run on Cloudflare Workers | Your IP address, the time, and that the request came from "SynSeeder". It carries no ID, name or version number |

The answers hold nothing personal: the server's map, score and player counts, GitHub's release details, SynSeeder's own files, and, from the seed-call service, only a random number for the latest seed call and how many seconds old it is.

We run the seed-call service on Cloudflare Workers, and the same service runs the bot. Cloudflare handles each request to it for us ([Cloudflare's privacy policy](https://www.cloudflare.com/privacypolicy/)). We've switched off its request logs and we don't save single requests, so we keep no record of who checked or when. In Cloudflare's dashboard we look only at totals, such as how many requests came in a day. If something breaks, we may watch requests live for a short time to fix it, which can show IP addresses, but we don't save them. Cloudflare may still keep its own records of requests for a while, for example to stop attacks. Because the app checks about once a minute, those records could show when your PC was on and unlocked. Cloudflare runs the service in data centres around the world, so your IP address and Discord details can be handled outside your country, including in the United States. Cloudflare says it follows the EU-U.S. Data Privacy Framework for this.

We don't run the stats page. We couldn't find a privacy policy for it, so we can't tell you whether its owners keep a record of these requests. Requests to it pass through Cloudflare, which handles them for whoever runs the stats page ([Cloudflare's privacy policy](https://www.cloudflare.com/privacypolicy/)). GitHub handles its requests under the [GitHub General Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).

The **Terms of Service** and **Privacy Policy** links at the bottom of SynSeeder's window open these documents on GitHub in your web browser. That happens only when you click one.

**Turning updates off.** Press **Save** once in SynSeeder so the settings file exists, then close SynSeeder. Paste `%APPDATA%\SynSeeder` into File Explorer's address bar and open `config.json` in Notepad. Change `"auto_update": true` to `"auto_update": false` and save the file. Type false in small letters with no quote marks around it, and leave everything else as it is. If the file has a mistake in it, SynSeeder ignores the whole file and updates come back on.

## The SynSeeder bot on Discord

The SynSeeder bot lets people with the Syngineers role call a seed with the **/seed** command. It works in one Discord server only, SYNDICATE ([discord.gg/syn-hll](https://discord.gg/syn-hll)), and turns /seed down anywhere else. It runs on the same Cloudflare service as the seed calls. It only gets /seed commands, and it doesn't read other messages in the server.

When someone uses /seed, Discord sends the bot what it sends with any command. That includes their Discord user ID, their names (user name, display name and server nickname), profile picture, roles and permissions, when they joined the server, and the language their Discord is set to. It also includes the server and channel it was used in. The bot uses the roles, server and channel to check that the person may call a seed there. It ignores the rest. Cloudflare handles all of it for us, with request logs switched off.

The bot then reads the game server's public player count. It calls a seed only if the server has fewer than 50 players, no seed was called in the last 30 minutes, and fewer than 4 were called today. A call lasts 15 minutes. If the bot turns a call down, only the caller sees why. If it calls a seed, it replies in the channel. The reply can ping up to two roles in the server, for players who want to hear about seed calls. It doesn't name the person who called, but Discord shows who used /seed above it, as it does for any command. That reply is the only record of who called, and the bot doesn't save a copy. Server moderators can delete it like any other message.

The bot keeps only what its limits need: a random number for the latest seed call, when it was made, and how many calls were made today. It keeps nothing else about the people who use /seed. It doesn't know which Discord users have Seed when pinged ticked.

Everything you do in Discord, including using /seed and seeing the bot's reply, is also handled by Discord under its own [privacy policy](https://discord.com/privacy).

## The game, Steam or Epic, and the server

When SynSeeder starts the game, everything that normally happens when you play happens as usual. Other people run each of these, under their own rules:

- Steam or Epic signs you in, records play time and may show friends that you're playing ([Steam Privacy Policy](https://store.steampowered.com/privacy_agreement/), [Epic Games Privacy Policy](https://legal.epicgames.com/epicgames/privacy-policy)).
- The game and its anti-cheat, Easy Anti-Cheat, collect what they normally do. The game's website points to Team17's [Privacy and Cookie Notice](https://www.team17.com/privacy-policy/), but that notice covers Team17's website and doesn't say what the game collects. Easy Anti-Cheat is run by Epic Games.
- The server's admins see you like any other player. Their admin tool, CRCON, can record your player name and past names, your platform ID (such as your Steam ID), when you joined and left, your kills and your chat. If it's set up to, it can also look up your Steam profile, such as your country and any bans. It can show some of this on public stats pages.

SynSeeder doesn't control any of this, and none of it passes through us. It also clicks "Yes" on admin messages so the run can carry on, so you may not see a message an admin sends you during a run.

## Sending your log or screenshots to someone

Your log and screenshots leave your PC only if you send them, for example when asking for help after a game update breaks something. Check them first: the log can show your Windows user name, and screenshots can show your in-game name, other players' names and chat. Crop or blank out anything you'd rather not share, especially before posting in a public GitHub issue.

If you send them to us privately, on [Discord](https://discord.com/users/132721731096936448) (user ID 132721731096936448), we use them only to work out what went wrong. We don't share them with anyone else, and we delete our copies once the problem is fixed. Discord handles those messages under its own [privacy policy](https://discord.com/privacy). Anything you post in a public GitHub issue or a chat can be seen and saved by anyone, and we can't take it back.

## Removing everything SynSeeder put on your PC

Four steps remove all of it. If you've already deleted the app, do this instead of step 1: open Task Scheduler from the Start menu and delete the tasks named SynSeeder and SynSeeder seed calls.

1. Open SynSeeder, press **Stop seeding** if a run is going, untick **Seed automatically** and **Seed when pinged**, and press **Save**. This deletes the scheduled tasks.
2. Close SynSeeder.
3. Delete the folders `%APPDATA%\SynSeeder` and `%LOCALAPPDATA%\SynSeeder` (paste each path into File Explorer's address bar to find it).
4. Delete the SynSeeder.exe you downloaded.

Unless you've sent us files, we never receive any of this, so there's nothing to delete on our side. The seed-call service and the bot keep nothing about you either. The only trace is the bot's reply to /seed in Discord, where Discord shows who used the command.

## Your rights, children, changes and contact

**Your rights.** Privacy laws such as the GDPR and the CCPA give you rights over personal data that a developer holds about you. We don't hold any, unless you've sent us your log or screenshots. The seed-call service sees your IP address, and the bot sees your Discord details when you use /seed, but only for a moment, and we don't keep them. If you've sent us files, message us privately on [Discord](https://discord.com/users/132721731096936448) and we'll tell you what we still have and delete it. The bot's replies to /seed are Discord messages. To have one removed, ask a moderator of that server, or message us on Discord and we'll help get it removed. Everything else listed above is on your PC and under your control.

**Children.** SynSeeder and its bot aren't meant for children. Use the app, and /seed, only if you're 18 or older. The Syngineers role, which /seed needs, should go only to adults.

**Changes.** If the app, the seed-call service or the bot will collect, keep or send anything new, we'll update this policy and the date at the top by the time the change happens. That includes turning the service's request logs back on. Updates install themselves, so check this page now and then, or turn updates off if you'd rather decide for yourself.

**Contact.** Questions about this policy: open an issue at [github.com/waterjugs/SYN-Seeder/issues](https://github.com/waterjugs/SYN-Seeder/issues). For anything about your own files, message us privately on [Discord](https://discord.com/users/132721731096936448) instead. Issues are public, so don't paste your log or screenshots there without checking them first. To report a problem with the bot, or someone misusing /seed, open an issue or message us on Discord. We read every report and act on the ones that need it.

Using SynSeeder is also covered by the [SynSeeder Terms of Service](TERMS.md).
