# The SynSeeder bot

This folder is a small Discord bot that runs on Cloudflare for free. It lets
members of the **SYNDICATE** Discord server (discord.gg/syn-hll) who have the
**Syngineers** role start a seed from Discord. It works in that server only,
and it needs no new roles.

1. A Syngineer types **/seed** in the SynSeeder channel.
2. The bot checks the call (see below). If it's fine, it replies in the
   channel: "Time to hop in the Syndicate | Competitive Server to get it
   seeded. Called by @name." It can also ping one or two roles, if you
   choose them in step 6.
3. Every PC with **Seed when pinged** ticked in SynSeeder (version 1.1.0 and
   later) checks the bot about once a minute. It sees the call and starts its
   normal seeding run if nobody is using that PC. If someone is, it asks
   them first.

The bot never talks to anyone's PC. The PCs come and ask it.

## What the bot checks

A seed is called only if all of these are true. Otherwise the bot says why,
and only the person who typed /seed sees that answer.

- /seed was used in the SYNDICATE server and in the SynSeeder channel. The
  server is built into the bot's code, so it can't be pointed anywhere else.
- The person has the Syngineers role. Server admins need it too.
- The game server has fewer than 50 players. If the bot can't read the player
  count, it doesn't call a seed.
- No seed was called in the last 30 minutes, and fewer than 4 today. "Today"
  runs from midnight to midnight US Eastern time.
- All of this takes less than about 2 seconds. Discord drops replies that
  come after 3, so the bot calls a seed only while its reply can still get
  there in time.

A call lasts 15 minutes. The bot's reply in the channel is the only record of
who called. The bot keeps only the latest call's random number, when it was
made, and how many calls were made that day, nothing about people. Its
request logs are switched off. If something goes wrong at Cloudflare while
a seed is being called, and the bot can't tell whether it went through, it
says so in the channel and names who tried. The
[Privacy Policy](../PRIVACY.md) promises all of this, so keep it that way.

## Its web addresses

Once it's set up, the bot lives at `https://synseeder.YOUR-SUBDOMAIN.workers.dev`.

| Address | What it's for |
| --- | --- |
| `/interactions` | Where Discord sends /seed. It goes in the Developer Portal. |
| `/seed-call` | What the PCs check. It shows `{"call":null}`, or a call's random number and its age in seconds. Open it in your browser to see. |
| `/` | Says "SynSeeder's seed-call service is running." |

The address is built into SynSeeder. **Never rename the Worker, change your
workers.dev subdomain, or delete the Worker or your Cloudflare account.**
PCs with old versions would stop seeing calls, and someone else could take
the address.

## Setting it up

You do every step yourself. It takes about 30 minutes. Start once this
`bot` folder is on the main branch on GitHub. Do the steps in this order,
because each one needs the one before it. Keep this page open in one tab and
work in another.

You'll copy a few things from one place to another. None of them are
passwords except the bot token in step 8, and that one you never save.

### 1. Turn on two-step login

Turn on two-step login (2FA) for your GitHub, Cloudflare and Discord accounts.
Anyone who gets into one of them could start seeds on everyone's PCs.

- GitHub: Settings > Password and authentication > Two-factor authentication.
- Discord: User Settings > My Account > Enable Two-Factor Auth.
- Cloudflare: you'll do this in step 3, right after you sign up.

### 2. Make the bot in the Discord Developer Portal

1. Go to <https://discord.com/developers/applications> and sign in.
2. Press **New Application**. Name it `SynSeeder`, tick the box to agree to
   Discord's terms, and press **Create**.
3. On **General Information**:
   - Paste `https://github.com/waterjugs/SYN-Seeder/blob/main/TERMS.md` into
     **Terms of Service URL**.
   - Paste `https://github.com/waterjugs/SYN-Seeder/blob/main/PRIVACY.md` into
     **Privacy Policy URL**.
   - Press **Save Changes**.
   - Leave this tab open. You'll copy the **Public Key** from here in step 4,
     and the **Application ID** in steps 7 and 8.
4. On **Installation**:
   - Under **Installation Contexts**, untick **User Install** so only
     **Guild Install** is ticked.
   - Set **Install Link** to **None**, and press **Save Changes**.
5. On **Bot**:
   - Turn **Public Bot** off, so only you can add it to a server. Press
     **Save Changes**.
   - Leave all three **Privileged Gateway Intents** off. The bot doesn't need them.

### 3. Put the bot on Cloudflare

1. Sign up for a free account at <https://dash.cloudflare.com/sign-up>.
   Then turn on two-step login straight away: **My Profile > Authentication**.
2. Open **Workers & Pages**. Next to **Your subdomain**, press **Set up** (or
   **Change**) and pick a workers.dev subdomain you'll keep for good, such as
   waterjugs or another nickname. Don't use your real name or your email
   name: everyone who uses SynSeeder will see it, and it can never change. If
   Cloudflare already filled one in that shows your name, press **Change**. It
   becomes part of the bot's address, so set it before you go on.
3. Press **Create application**, and pick **Import a repository** (or
   **Connect GitHub**).
4. When GitHub asks which repositories Cloudflare may see, pick
   **Only select repositories**, choose **SYN-Seeder**, and press **Install**.
5. Back on Cloudflare, pick **SYN-Seeder** and fill in:
   - **Project name**: `synseeder` (exactly this, in small letters).
   - **Build command**: `npm test` (it checks the bot before every deploy, and
     a failed check stops the deploy).
   - **Deploy command**: `npx wrangler deploy`
   - Open **Advanced settings** and set **Root directory** (or **Path**) to `bot`.
6. Press **Deploy** and wait for it to finish. Your Worker's page opens.
7. On the Worker's page, open **Settings > Build** and:
   - Under **Branch control**, set the production branch to **main**, and
     untick **Enable Preview Builds** (or **Builds for non-production
     branches**). Test versions would get public addresses of their own.
   - Under **Build watch paths**, set **Include paths** to `bot/*`, so only
     changes to the bot redeploy it.
8. Open your Worker's address in your browser. You'll find it on the Worker's
   page under **Domains & Routes** (or **Visit**). It should say
   "SynSeeder's seed-call service is running." Right after the first deploy
   it can take a minute to start working.
   Then add `/seed-call` to the end of the address. It should show `{"call":null}`.
9. **Send Claude this address**, so it can be built into SynSeeder. It isn't
   a secret.

### 4. Give the Worker the Public Key

1. On the Worker's page, open **Settings > Variables and Secrets** and press **Add**.
2. Type: **Text**. Variable name: `DISCORD_PUBLIC_KEY`. Value: the
   **Public Key** from the Developer Portal's General Information page
   (press **Copy** there).
3. Press **Deploy**. The change is live straight away.

### 5. Tell Discord the bot's address

1. On the Developer Portal's **General Information** page, paste your
   Worker's address with `/interactions` on the end into
   **Interactions Endpoint URL**, for example
   `https://synseeder.YOUR-SUBDOMAIN.workers.dev/interactions`.
2. Press **Save Changes**. Discord sends the bot a test, and saves only if the
   bot answers it.

If Discord says the address couldn't be verified, the Public Key in step 4
doesn't match. Copy it again and check there are no spaces around it.

### 6. Copy two ID numbers

You don't make any roles. The bot uses SYNDICATE's existing **Syngineers**
role. It also works in one channel only. Pick the SYNDICATE channel where
/seed should work, with its admins if you're not one. This guide calls it the
SynSeeder channel.

1. Turn on Developer Mode: **User Settings > Advanced > Developer Mode**.
   This adds **Copy ID** to Discord's right-click menus.
2. In the SYNDICATE server, copy each ID and add it on Cloudflare as in
   step 4 (Type **Text**, then **Deploy**):

| Variable name | Where to copy it |
| --- | --- |
| `SYNSEEDER_CHANNEL_ID` | Right-click the SynSeeder channel > **Copy Channel ID** |
| `SEED_CALLER_ROLE_ID` | Click the name of anyone who has Syngineers (in the member list, for example). In their profile, right-click **Syngineers** > **Copy Role ID**. If you can't see the role there, open their full profile |

Each one is a long number. If one is missing or isn't a number, /seed tells
you which. If /seed names a channel or role that looks wrong, copy that ID
again.

You don't need the server's ID: the bot already knows SYNDICATE's.

**Optional: roles to ping.** By default the bot's reply pings nobody. If
SYNDICATE already has a role that players join to hear about seeds, you can
add a third setting, `SEEDERS_ROLE_ID`, with that role's ID. Copy it the
same way: click someone who has the role, then right-click the role in their
profile > **Copy Role ID**. Then each call pings that role. To ping two
roles, put both IDs in the setting with a comma between them, like
`111111111111111111,222222222222222222`. The bot pings at most two, because
the Privacy Policy says so. Leave the setting out for no ping. If the
setting's name is misspelled, /seed still calls seeds but pings nobody. If
its value isn't one or two numbers, /seed says so.

### 7. Invite the bot to the SYNDICATE server

Steps 7 and 9 need admin rights in SYNDICATE (at least **Manage Server**
and **Manage Roles**). If you don't have them, ask a SYNDICATE admin to do
them with you:

- In 7.2, only you can add the bot, because it's private (step 2.5), and
  only to a server where you have **Manage Server**. So either the admin
  gives you **Manage Server** for a while, or you turn **Public Bot** on for
  a moment on the Developer Portal's **Bot** page and press **Save
  Changes**. Then send the admin the link from 7.1. As soon as they tell you
  Discord says SynSeeder was added, turn **Public Bot** off again and press
  **Save Changes**. (Don't wait to see the bot in the member list. It always
  shows as offline, and SYNDICATE is too big to list offline members.)
- The admin can do step 9 for you, and 7.3 if you chose roles to ping.

Do steps 7 to 9 in one go. Until step 9 is done, everyone in the server sees
/seed, though the bot turns down anyone without the Syngineers role.

1. Copy this link, and replace `APPLICATION_ID` with the **Application ID**
   from the Developer Portal's General Information page:

   `https://discord.com/oauth2/authorize?client_id=APPLICATION_ID&scope=bot+applications.commands&permissions=0`

2. Open it in your browser, pick **SYNDICATE**, and press **Authorize**.
   The bot joins with no server-wide permissions. It doesn't need any to
   answer /seed.
3. Only if you chose roles to ping in step 6: let the bot ping them in the
   SynSeeder channel. Right-click the channel > **Edit Channel >
   Permissions > Advanced permissions**, press **+** next to
   **Roles/Members**, and pick the bot, **SynSeeder** (it's listed under
   Members). Set these three to allow (the green tick), and press **Save
   Changes**:
   - **View Channel**
   - **Send Messages**
   - **Mention @everyone, @here, and All Roles**. That sounds big, but it
     only works in this one channel, and the bot only ever pings the roles
     you chose.

   Without a role to ping, skip this. The bot can answer /seed without any
   channel permissions.

### 8. Add the /seed command

1. Download [add-seed-command.ps1](add-seed-command.ps1): open it on GitHub,
   press the download button (**Download raw file**), and save it in your
   **Downloads** folder.
2. Open **Downloads** in File Explorer. Click the address bar at the top,
   type `powershell` and press Enter. A PowerShell window opens (it may be
   blue or black).
3. Paste this line into that window with a right-click, and press Enter:

   `powershell -NoProfile -ExecutionPolicy Bypass -File .\add-seed-command.ps1`

   (This runs just this one script. It doesn't change any Windows settings.)
4. It asks for two things. Paste each one with a right-click and press Enter:
   - the **Application ID** (General Information),
   - the **bot token**: on the Developer Portal's **Bot** page press
     **Reset Token**, then **Copy**. It stays hidden while you paste it.
5. When it finishes, whether it says "Done" or not, go back to the **Bot**
   page and press **Reset Token** once more, and don't copy the new one. The
   bot never needs a token, so now no working token exists anywhere. If it
   didn't work, fix what it says and run it again, with a fresh token from
   **Reset Token** and **Copy**.

### 9. Let only Syngineers use /seed

Do this on a computer (the Discord app or discord.com), not the phone app.

Until you do this step, everyone in the server sees /seed, though the bot
turns down anyone without the Syngineers role.

1. In Discord, open **Server Settings > Integrations**, and next to
   **SynSeeder** press **Manage**.
2. Under **Roles & Members**, turn **@everyone** off (the red cross). Then add
   **Syngineers** and allow it (the green tick).
3. Under **Channels**, turn **All Channels** off (the red cross). Then add your
   SynSeeder channel and allow it (the green tick).
4. If Discord shows **Save Changes**, press it.

Now only Syngineers see /seed, and only in that channel. The bot checks
both again itself, because server admins can always use every command.

### 10. Try it

Server admins can use /seed whatever step 9 says. So the first check needs
someone who isn't an admin.

1. Ask a Syngineer who isn't a server admin whether /seed shows up when they
   type `/` in the SynSeeder channel.
   Then ask someone who has neither the role nor admin rights whether it
   doesn't (admins always see every command). If either is wrong, check
   step 9.
2. Check you have the **Syngineers** role yourself: the bot turns down
   anyone without it, even server admins. The bot itself doesn't need the
   role.
   If you don't, ask a SYNDICATE admin for it, or ask a Syngineer to do 2
   and 3 and tell you what they see.
   In the SynSeeder channel, type `/seed` and press Enter.
   - If the server has fewer than 50 players, the bot replies to everyone.
     Open the `/seed-call` address from step 3: it now shows the call and
     its age. If you chose roles to ping, ask someone with each one whether
     Discord notified them. If not, check step 7.3 and `SEEDERS_ROLE_ID`
     (step 6).
   - If it has 50 or more, only you see a message saying it doesn't need a seed.
3. If the bot called a seed in 2, type `/seed` again. Only you see a message
   saying a seed was called less than 30 minutes ago (or, if that was the 4th
   seed today, that 4 seeds have been called today). If it said the server
   doesn't need a seed, do 2 and 3 another time, when it has fewer than 50
   players.

If /seed doesn't show up for a Syngineer, check step 9, and that the
channel lets them **Use Application Commands** (it does unless someone
turned it off).
If the bot always says it couldn't read the player count, the stats page may
be refusing Cloudflare. Tell Claude.

### 11. Keep the Syngineers role for trusted adults

- Everyone with **Syngineers** can call seeds, and each call can start the
  game on every PC with Seed when pinged ticked. So check with SYNDICATE's
  admins that the role goes only to adults they trust.
- A role to ping (step 6) only makes Discord notify people. The tick box in
  SynSeeder is what makes a PC seed.

## Good to know

- **It's free up to a limit.** Cloudflare's free plan allows 100,000 requests
  a day for the whole account, reset at 00:00 UTC (7 or 8 pm US Eastern).
  Each PC that checks once a minute for 15 hours uses about 900. Past the
  limit, every request to the bot fails until 00:00 UTC: /seed doesn't
  answer and PCs see no call. SynSeeder's own daily seed at each PC's chosen
  time still runs. The address isn't secret, so someone could also use up
  the requests on purpose.
- **Changes deploy themselves.** When a change to this folder is merged into
  main, Cloudflare checks it with `npm test` and deploys it. If a check
  fails, nothing is deployed and the old version keeps running. The IDs and
  the Public Key stay where they are.
- **Logs stay off.** Don't turn on Workers Logs or Traces for this Worker. The
  Privacy Policy says they're off, and changing that needs 14 days' notice.
- **If the bot is down,** /seed shows "The application did not respond" and PCs
  see no call. Nothing else breaks. If Discord emails or messages you that it
  removed your Interactions Endpoint URL, redo step 5 once the bot's address
  answers again.

## For whoever changes the code

The code is plain JavaScript with no packages at run time. `wrangler` (in
`package.json`) is only Cloudflare's deploy tool.

- `src/index.js`: the Worker. It wires the pieces together.
- `src/handler.js`: what each address does, and /seed's checks and replies.
- `src/rules.js`: the limits (50 players, 30 minutes, 4 a day in US Eastern
  time, 15 minutes).
  They're promised in PRIVACY.md and TERMS.md, so change those too.
- `src/flag.js`: the Durable Object that holds the seed-call flag.
- `src/discord.js`: checks Discord's signature on each request.
- `src/stats.js`: reads the player count from the server's stats page.
- `src/config.js`: reads the settings typed into Cloudflare.

Run the tests with `npm test` in this folder (Node.js 22 or later).
