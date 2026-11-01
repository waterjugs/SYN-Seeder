using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Threading;

namespace SynSeeder
{
    /// <summary>
    /// One seeding run: start the game, get onto the server with a squad of our own, stay until the server
    /// has enough players, then leave. Each tick looks at the screen, works out which menu it is and does
    /// the one thing that moves it forward, so a fresh launch, a kick to the menu or a new map are all handled.
    /// </summary>
    sealed class Seeder
    {
        static readonly string[] Overlays = { "admin_yes", "game_menu_leave" };
        static readonly string[] Screens =
        {
            "admin_yes", "game_menu_leave", "deploy_button", "roles_confirm", "select_force", "create_unit",
            "switch_team", "server_row", "browser_search", "browser_refresh", "menu_enlist",
        };
        static readonly RectangleF InfantryCreate = RectangleF.FromLTRB(0.29f, 0.10f, 0.53f, 0.22f);
        static readonly RectangleF FactionBadge = RectangleF.FromLTRB(0.0f, 0.75f, 0.12f, 0.95f);
        static readonly RectangleF UsCard = RectangleF.FromLTRB(0.05f, 0.30f, 0.50f, 0.55f);
        static readonly RectangleF NvaCard = RectangleF.FromLTRB(0.50f, 0.30f, 0.95f, 0.55f);
        static readonly RectangleF CreateUnitButton = RectangleF.FromLTRB(0.55f, 0.60f, 0.95f, 0.90f);
        const int IdleBeforeTakeover = 15;

        readonly Config config;
        readonly Game game;
        readonly Vision vision;
        readonly CancellationToken stop;
        readonly Action<string> status;
        string side = "allies";
        bool switchedTeam, inGame;
        int adminClicks;
        DateTime lastRefresh = DateTime.MinValue;

        public Seeder(Config config, Vision vision, CancellationToken stop, Action<string> status)
        {
            this.config = config;
            this.vision = vision;
            this.stop = stop;
            this.status = status;
            game = new Game(config);
        }

        public void Run()
        {
            var end = DateTime.UtcNow.AddMinutes(config.MaxMinutes);
            var players = Stats.FetchAsync(config.CrconUrl).GetAwaiter().GetResult();
            if (players != null && players.Players >= config.SeededThreshold)
            {
                status($"Already seeded ({players.Players} players). Nothing to do.");
                return;
            }
            if (game.Find() == null && !game.Launch(stop))
            {
                status("The game didn't start.");
                return;
            }
            bool fresh = true;
            while (DateTime.UtcNow < end)
            {
                stop.ThrowIfCancellationRequested();
                players = Stats.FetchAsync(config.CrconUrl).GetAwaiter().GetResult();
                if (players != null)
                {
                    side = players.WeakerSide;
                    status($"{players.Players} of {config.SeededThreshold} players");
                    if (players.Players >= config.SeededThreshold)
                    {
                        int minutes = new Random().Next(config.LeaveDelayMinutes + 1);
                        status($"Seeded. Leaving in {minutes} min.");
                        Wait(minutes * 60);
                        game.Close();
                        return;
                    }
                }
                if (!inGame && !GetIn(TimeSpan.FromMinutes(fresh ? 6 : 4), fresh))
                    status("Still trying to get in...");
                fresh = false;
                Nudge();
                Wait(config.PollSeconds);
            }
            status("Stopped after " + config.MaxMinutes + " minutes.");
        }

        void Wait(int seconds)
        {
            if (stop.WaitHandle.WaitOne(TimeSpan.FromSeconds(seconds)))
                stop.ThrowIfCancellationRequested();
        }

        /// <summary>Brings the game in front, but only once nobody has used the PC for a while.</summary>
        bool Focus()
        {
            IntPtr hwnd = game.Window();
            if (hwnd == IntPtr.Zero || !Native.DesktopUnlocked())
                return false;
            if (Native.InFront(hwnd))
                return true;
            if (Native.IdleSeconds() < IdleBeforeTakeover)
                return false;
            return Native.BringToFront(hwnd);
        }

        string CurrentScreen()
        {
            Rectangle area = game.Area();
            vision.SetFrame(Vision.Capture(area), area);
            return Screens.FirstOrDefault(name => vision.Find(name) != null);
        }

        bool GetIn(TimeSpan timeout, bool freshLaunch)
        {
            var deadline = DateTime.UtcNow + timeout;
            var seen = new HashSet<string>();
            switchedTeam = inGame = false;
            bool deployed = false;
            int quiet = 0;
            while (DateTime.UtcNow < deadline)
            {
                stop.ThrowIfCancellationRequested();
                if (game.Find() == null)
                    return false;
                if (!Focus())
                {
                    Wait(2);
                    continue;
                }
                string name = CurrentScreen();
                if (name != "admin_yes")
                    adminClicks = 0;
                if (name == null)
                {
                    if (deployed || (!freshLaunch && seen.All(Overlays.Contains)))
                    {
                        inGame = true;
                        if (++quiet >= 3)
                            return true;
                    }
                    else if (freshLaunch && seen.All(Overlays.Contains))
                        Native.Press(' ');  // splash: "press any button"
                    Wait(2);
                    continue;
                }
                quiet = 0;
                seen.Add(name);
                if (!Overlays.Contains(name))
                {
                    deployed = name == "deploy_button";
                    inGame = false;
                }
                Handle(name);
                Wait(2);
            }
            return false;
        }

        void Click(Point? at)
        {
            if (at == null)
                return;
            Native.Click(at.Value.X, at.Value.Y);
            Thread.Sleep(100);
            Rectangle area = game.Area();
            Native.MoveCursor(area.Left + 5, area.Top + area.Height / 2);  // so hover highlights don't change the next match
        }

        void Handle(string name)
        {
            switch (name)
            {
                case "admin_yes":
                    bool menu = Screens.Except(Overlays).Any(other => vision.Find(other) != null);
                    if ((inGame && !menu) || (++adminClicks > 2 && adminClicks % 2 == 1))
                        Native.Press('y');
                    else
                        Click(vision.Find("admin_yes"));
                    break;
                case "game_menu_leave":
                    Native.Press('\x1b');
                    break;
                case "deploy_button":
                    Native.Press('f');
                    inGame = true;
                    break;
                case "roles_confirm":
                    Native.Press('f');
                    break;
                case "select_force":
                    switchedTeam = true;
                    Click(side == "axis" ? vision.Find("force_nva", NvaCard) ?? vision.Find("force_us", UsCard)
                                         : vision.Find("force_us", UsCard) ?? vision.Find("force_nva", NvaCard));
                    break;
                case "create_unit":
                    Click(vision.Find("create_unit_button", CreateUnitButton));
                    break;
                case "switch_team":
                    string current = vision.Find("faction_nva", FactionBadge) != null ? "axis" : "allies";
                    if (side != current && !switchedTeam)
                    {
                        switchedTeam = true;
                        Click(vision.Find("switch_team"));
                        break;
                    }
                    // Always lead a new squad of our own, never join someone else's.
                    Click(vision.Find("infantry_create", InfantryCreate));
                    break;
                case "server_row":
                    var row = vision.Find("server_row");
                    var joins = vision.FindAll("browser_join");
                    if (row != null && joins.Count > 0)
                        Click(joins.OrderBy(join => Math.Abs(join.Y - row.Value.Y)).First());
                    break;
                case "browser_search":
                    Click(vision.Find("browser_search"));
                    Thread.Sleep(500);
                    Native.TypeText(config.ServerSearch);
                    Native.Press('\r');
                    lastRefresh = DateTime.UtcNow;
                    break;
                case "browser_refresh":
                    if (DateTime.UtcNow - lastRefresh >= TimeSpan.FromSeconds(20))
                    {
                        Native.Press('r');
                        lastRefresh = DateTime.UtcNow;
                    }
                    break;
                case "menu_enlist":
                    Click(vision.Find("menu_enlist"));
                    Wait(3);
                    break;
            }
        }

        /// <summary>A small strafe so the idle kick doesn't trigger.</summary>
        void Nudge()
        {
            if (!inGame || !Focus())
                return;
            Native.KeyDown('a');
            Thread.Sleep(300);
            Native.KeyUp('a');
            Native.KeyDown('d');
            Thread.Sleep(300);
            Native.KeyUp('d');
        }
    }
}
