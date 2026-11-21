# Afterlap

A one-tap arcade game: drive laps around a ring while every lap you finish comes back the other way as a ghost. Tap to switch lanes, grab stars, don't hit yourself.

The game itself is a single HTML/JavaScript file. The iOS app is a small Swift wrapper that shows that file full-screen, with everything bundled inside the app.

## What's in this repository

| Path | What it is |
|---|---|
| `src/afterlap.html` | **The game.** Edit this file to change the game. |
| `web/index.html` | Standalone page built from `src/afterlap.html`. The iOS app loads this one. Don't edit it by hand. |
| `ios/` | The iOS app: Swift source, app icon, and `project.yml` (turned into an Xcode project with XcodeGen). |
| `tools/build-web.ps1` | Rebuilds `web/index.html` from `src/afterlap.html`. |
| `tools/make-icon.ps1` | Redraws the 1024×1024 app icon (Windows only). |
| `docs/github-upload.md` | How to put this project on GitHub without installing anything. |
| `docs/ios-submit-guide.md` | Step-by-step guide for building on a Mac and submitting to the App Store. |
| `docs/privacy-policy.md` | Privacy policy text to publish (Apple requires a privacy policy URL). |
| `docs/online-setup.md` | Setting up the free Supabase project that runs online rooms. |
| `docs/leaderboard-setup.md` | Setting up leaderboards, accounts and cloud saves (email codes, test mode, moderation). |
| `docs/premium-skins-setup.md` | Creating the premium skin products in App Store Connect and testing purchases. |
| `supabase/setup.sql` | The online rooms database. Run once in Supabase. |
| `supabase/leaderboard.sql` | Leaderboards, accounts, verified runs and cloud saves. Run after `setup.sql`. |

## Changing the game

1. Edit `src/afterlap.html`.
2. Rebuild the app page (Windows):
   ```
   powershell -ExecutionPolicy Bypass -File tools\build-web.ps1
   ```
   On a Mac with PowerShell installed: `pwsh tools/build-web.ps1`.
3. Commit both `src/afterlap.html` and `web/index.html`.

You can also open `web/index.html` directly in a browser to play it.

## Story: "Do Not Press"

The whole story is one joke: you pressed the button that said DO NOT PRESS and got stuck in a time loop, so every lap you drive comes back. It never gets in the way of play, and there are no new gameplay rules.

- **First-time intro / tutorial** (about 15 seconds, shown once): a scripted lap on the real ring, in three steps. It has its own teal look (teal track, edges, lane dashes and start line, a TUTORIAL tag above the ring, teal tap prompts) so it never reads as a real run; stars stay gold and glitches red, as in the game. (1) Dot presses the big red button, finishes a lap, and that lap comes back as a ghost; everything freezes until the player taps to dodge. (2) Three stars appear in Dot's lane; collecting all three shatters the ghost ("3 stars in one lap shatter your oldest ghost"). Tutorial stars don't go into the wallet. (3) A red glitch appears ahead ("They show up from lap 11"); the game freezes again until the player taps to dodge, then the real run starts with a clean lap 1. Tapping before the ghost appears skips it. It's saved as seen in `rerun-intro`, and players who already have a score never see it. **Tutorial** on the title screen plays it again.
- **Messages:** game-over lines (including "Taken out by you, from 3 laps ago"), close-call pop-ups ("Hi me!", "Excuse me!"), and a joke under a skin you just bought. They live in `LOOP_QUIPS`, `CLOSE_FIRST` and `UNLOCK_QUIPS`, next to `CLOSE_NAMES`. New players (under 12 runs) always get the useful "the switch that set this trap is circled" line instead of a joke.
- **Face reactions:** the dot blinks, glances at a ghost passing in the other lane, sweats after a close call, and falls asleep (Zzz) after 20 seconds on the title screen.
- **Rewind:** pressing Again after a crash plays a half-second VHS rewind over the new run. It's visual only and the run starts straight away. It's turned off with reduced motion.
- **Rare surprises:** about 1 run in 300, one of the first three ghosts wears a party hat; lap 100 (and every 100 after) gets confetti.

## Tuning

Gameplay numbers (ghost speed, hitbox, grace period, close-call star bonus) are in the "Tuning knobs" block at the top of the script in `src/afterlap.html`. Speed, difficulty and spawning live in the "Gameplay engine" block (below).

## Gameplay engine (solo and online)

Ghosts are always your own past laps; they're never generated. Everything else on the ring is, by five small parts in the "Gameplay engine" block:

| Part | Where | Job |
|---|---|---|
| Speed Controller | `speedAt(lap)`, `SPEED_CAP` | How fast the dot drives on each lap. |
| Difficulty Manager | `TIERS`, `tierParams(lap)` | One tier per 10 laps and its numbers. |
| Pattern Generator | `pickMood()`, `glitchPat()`, `starPat()` | Lays out each lap from templates with seeded randomness (new seed every run). |
| Fairness check | `ghostMeets()`, `solveLap()` | Only accepts a layout that can be survived at human pace while collecting all three stars. |
| Spawner | `planLap()` | Tries layouts within a 5–6 ms budget, then hands stars, bonus stars and glitches to the run. |

**Speed.** 100% is the first lap (4.6 s). Laps 1–10 add 2.5% each (lap 10 = 123%), then speed eases toward a 178% cap: about 136% at lap 20, 160% at 50 and 174% at 100. The HUD's **SPEED** shows exactly this: your dot's speed compared with lap 1. (Ghosts replay at 61.8% of the speed of the lap they recorded.) The cap keeps every lap longer than 2.5 s, which the online server also checks, so don't raise `SPEED_CAP` above 1.84 without changing `report_run` in `supabase/setup.sql`.

**Tiers.** Easy (1–10), Normal, Intermediate, Challenging, Hard, Expert, Advanced, Extreme, Insane, Master (91–100), then Endless. Players never see these names; they're labels for tuning. In a run, players see the speed and the tier's colour instead. Each tier in `TIERS` sets:
- `glitch`: the most glitches on one lap;
- `gap`: the shortest time between two glitches you have to weave between;
- `react`: the fastest tapping the fairness check assumes (one lane switch per that many seconds);
- `mood`: weights for the five lap moods.

Endless adds one glitch every 25 laps and tightens gaps slightly, both capped.

**Lap moods** (picked per lap, never three alike in a row, hard laps come in short runs with a breather after them, and the lap after each milestone is a breather):
- **breathe:** no glitches, easy stars;
- **precision:** a two-glitch gate to weave through;
- **risk:** one star sits right before or after a ghost passes, or right behind a glitch, plus sometimes a gold +3 star;
- **rapid:** a quick run of 3–5 glitches;
- **mixed:** a long glitch "tunnel" in one lane plus singles.

**Glitches** (from lap 11) are red static blocking one lane for one lap. They always appear at least 0.9 s ahead, never sit on a star, and are only kept if the fairness check finds a way through alongside every ghost meeting. If your ghosts alone already make a lap a squeeze, that lap gets no glitches. Switching away from one at the last moment is a close call.

**Stars:** still three per lap (three in one lap shatter a ghost), now anywhere on the ring in varied spacings (spread, line, weave, risky). A lap's layout is never repeated within 80 laps. **Gold stars** (+3) and the rare **Star Rush** (6 bonus stars) pay into the wallet but don't count toward the shatter.

**Milestones:** every 10 laps a banner ("Lap 20!" with the new speed) appears, the SPEED readout flashes, and the next lap is a breather. In a run, the ring's centre shows the current speed in the tier's colour, and (once you have a best of 3+) how many laps to your best.

**Testing.** Set `engDebug = true` and `planLap()` records each lap's mood, glitch count, stars and the solver's own tap plan. A bot that follows that plan was run through more than 2,000 laps across laps 1–140: it never touched a glitch, and every lap it died on was one its own ghosts had already locked. Duel is unchanged (it keeps its own `SPEEDUP`/`MIN_LAP` and seeded stars).

## Duel (two players, one phone)

The title screen has a **Duel** button. Two players share the ring on one phone:

- P1 starts at 9 o'clock and taps the **left** half of the screen; P2 starts at 3 o'clock and taps the **right** half. On a keyboard, P1 is `A` (or `S`, `Z`, Left arrow) and P2 is `L` (or `K`, `M`, Right arrow).
- Each player's finished laps come back as ghosts in that player's colour (P1 orange, P2 cyan). **Only the other player's ghosts can hit you.**
- Each player has their own stars. Three in one lap shatter the rival's oldest ghost.
- The last dot still driving wins. If both crash on the same frame it's a tie.
- Each player picks a skin from the skins the device owns. The choice is saved in `rerun-duel`.

Stars picked up in a duel go into the device's wallet. Duels don't change the high score, awards or daily challenges. The series score (wins for each player) lasts until you go back to the menu.

The duel code is in the "Duel" block of the script. Stars come from a seeded random generator, so a match is fully decided by its seed and the tap times. An online version could send just those between two phones.

## Online (private rooms)

The title screen has an **Online** button. Two players on two devices each play their own normal game at the same time and see each other's progress live.

1. One player picks a name and taps **Create**. The game shows a 5-digit room code to share.
2. The other taps **Join**, types the code, sees whose room it is, and confirms.
3. The host taps **Start**. After a 3-second countdown, both start their own run.
4. A small panel under the top bar shows both names, lap counts and status (playing, eliminated, reconnecting).
5. When one player crashes, the other keeps going. When both are out, a results screen shows the winner (more laps), close calls and the series score. **Play again** reuses the same room once both players tap it.

Under the hood:

| Piece | Where |
|---|---|
| Server: rooms, codes, seats, timeouts, score checks | `supabase/setup.sql` (run once in your Supabase project) |
| Client | the "Online: private rooms" block in `src/afterlap.html` |
| Supabase connection details | `const ONLINE = { url, key }` in that block |
| Supabase JavaScript client | `web/vendor/supabase.js` (MIT licence next to it), loaded when someone starts a run, opens Ranks or opens Online |

Setup steps are in `docs/online-setup.md`. Until `ONLINE` is filled in, the Online screen says online play isn't set up, and the rest of the game is unaffected.

The game only sends the lap count, close calls and alive/out status, on each lap, close call and crash. All writes go through server functions that let each player change only their own row, reject laps that couldn't have been driven in the time played, and lock the free seat so two people can't take it at once.

Refreshing or reopening the app puts you back in your room. A run in progress can't survive a reload, so it ends at the last lap the server saw. Short connection drops show "Reconnecting…" and the run carries on. After 60 seconds of silence the server ends that player's run and marks them as left.

## Leaderboards and accounts

The trophy button on the title screen opens **Ranks**: Global, Region and Country boards (top 1,000, loaded 50 rows at a time), with your own rank on all three always shown at the top, even outside the top 1,000. Top three get gold, silver and bronze; NEW and ▲ PB tags mark new entries and improved bests; a green dot means that player is playing now. Regions: North America, Europe, Oceania, Asia, Southeast Asia, Latin America, Middle East & Africa (`COUNTRY_TABLE` in the game and `lb_countries` in `leaderboard.sql`; keep them in step).

- **Guests** play straight away, with everything saved on the device. Each solo run is timed by the server in the background, so a guest's best is already verified.
- **The invitation.** When a guest's run is a new verified best of 3+ laps that would make a top 1,000 (checked live against the board), a "You made the leaderboard!" screen offers **Claim my rank** or **Not now**. Not now keeps the claim waiting in Ranks and on the game-over card.
- **Accounts** use a 6-digit email code (no password). Creating one adds the email to the guest's existing player, so the ID, verified scores and all progress carry over. Signing in to an existing account from a guest hands the guest's verified runs to it with a one-time token. Then the player picks a display name (unique, 3–16 characters) and confirms a country (guessed from the connection or time zone; never GPS) with an option to hide it (hidden = Global board only).
- **Cloud save** keeps the whole progress (bests, stars, skins, awards, dailies, stats) online and merges between devices: skins and awards combine, bests and stats keep the higher value, and stars apply what each device earned or spent since the last sync, so nothing is lost or doubled.
- **New personal bests** for ranked players show "Climbed N places · OCEANIA #124 → #100" on the game-over card, and the rank line shows all three ranks.
- **Account screen**: player card, ID, joined date, stats, sync status, edit, sign out, delete account.

Score checks (server side): the dot's speed is fixed by the speed curve, so N laps take a known minimum time; finishes faster than that are rejected, each run can be finished once, run starts are rate-limited (one per 1.5 s, 600 a day), and scores far above everyone else's are stored as `flagged` and kept off the boards for review. Lane-switch times are stored with each run for audits and future replay checks. This stops edited requests, impossible scores, duplicates and spam; it can't fully stop a bot that genuinely plays in real time.

Setup, test mode and moderation: `docs/leaderboard-setup.md`. Client code: the "Accounts, leaderboards and cloud save" section of `src/afterlap.html`.

## Skins, awards and daily challenges

All of this is data near the top of the script, so adding content doesn't mean touching the game logic:

| List | What it holds |
|---|---|
| `THEMES` | The 19 earned skin sets (tabs in the Skins screen, after "All"). |
| `PTHEMES` | The 10 premium sets of 5 (Abyssal Depths, Ancient Pantheon, Celestial, Clockwork Age, Cyberpunk, Dark Fantasy, Elemental Lords, Legendary Heroes, Mythic Beasts, Otherworldly). |
| `SKINS` | 588 skins: 538 earned by playing and 50 premium. The original 158 come first, then the expansion (`XS(...)`, 20 per set), then the premium skins (`PS(...)`). |
| `SEASONS` | Date windows for the seasonal skins (Halloween, Christmas, Valentine, Spring, Summer). |
| `ACH` | 32 awards (9 of them secret). Each gives stars or a skin. |
| `DAILY` | The pool of daily challenges (easy, medium and hard). |

**Adding a skin:** add one line to `SKINS`. A look is built from reusable parts:

| Field | Parts list | What it is |
|---|---|---|
| `shape` | `SHAPES` (plus `pixel`, `ghost`) | Body outline: pumpkin, heart, egg, star, box, gem, flame, and more. Default is round. |
| `pat` | `PAT` | Pattern painted inside the body. |
| `deco` | `DECO` | One or more extras around the body (hats, ears, wings, horns). Use a list for several. |
| `eyes`, `mouth` | `EYES`, `MOUTHS` | Face style. |
| `trail` | `TRAILS` | What follows the player. |
| `fx` | built in | Animation: pulse, twinkle, orbit, flicker, fade, wobble, beat. |

The comment above `RARITY` lists every field, including the extra colours some parts read (`hat`, `ear`, `wing` and so on). The Bestiary set added the `bullHorns`, `noseRing` and `hydraHeads` decorations, and the optional colours `maneCol` (for `mane`), `hornCol` (for `horns` and `bullHorns`), `ring` and `neck`. Shapes stay inside one body radius and decorations are only drawn, so a skin never changes the hitbox.

`unlock` can be:
- a star price;
- `'set'`: the set's bonus skin, unlocked by owning the rest of the set;
- an award id from `ACH`;
- `{ ride: 25 }`: drive 25 laps wearing any skin from the same set;
- `{ season: 'xmas', ride: 120 }`: play one run during the season, or drive 120 set laps at any time.

Seasonal skins come back every year and always have the lap route, so nobody is locked out for good. The Summer window (15 Jun to 31 Aug) follows the northern hemisphere.

- `'premium'`: bought with real money (premium skins only, made with `PS(id, name, set, price, desc, look)`).

Expansion skins (made with `XS(set, rows)`) are marked `x: 1` and don't count towards a set's bonus skin, so the bonus requirements are exactly what they were before the expansion.

**Skins screen.** Two sections at the top: **Earned** (everything unlocked by playing) and **Premium**. Inside a section, set tabs and skins are sorted A to Z automatically (`localeCompare`), so a new skin lands in the right place without any manual ordering; hidden secret skins sort last. The "All" view adds a search box, filters for set, rarity and owned/locked, and sorting by set A–Z, name A–Z, rarity or newest. Every card and the preview show one status: Equipped, Owned, Unlock (enough stars or conditions met), Locked, or a price for premium skins.

**Premium skins** are cosmetic only: same shape radius, same hitbox, same speed. They use the extra `pfx` effects (auras, orbiting particles, wings, portals, rising bubbles, angler lures, turning gears, steam, sun discs, feathers, snowflakes) and premium trails, which are drawn only. To add a premium set, add it to `PTHEMES`; tabs sort A to Z by themselves. They are excluded from the collection awards and the "skins owned" count, so free players can still complete everything. Buying opens a sheet with the price, "one-time purchase, cosmetic only", and Buy / Not now; there are no pop-ups or reminders elsewhere. The purchase itself goes through `ios/Afterlap/Purchases.swift` (StoreKit 2) with product IDs `afterlap.skin.<id>`. In a browser there's no store, so premium skins can be previewed but not bought.

Progress is saved on the device in localStorage (`rerun-best`, `rerun-stars`, `rerun-owned`, `rerun-skin`, `rerun-muted`, `rerun-duel` for the two duel skins, `rerun-intro` once the intro has been seen, `rerun-name` and `rerun-online-room` and `rerun-online-auth` for online play, and `rerun-profile` for stats, awards, dailies and laps driven per set).

## Fonts

The game uses four fonts from Google Fonts, all under the SIL Open Font License (free for commercial use, including inside an app): Monoton, Pixelify Sans, Silkscreen and VT323. They are bundled in `web/fonts/` next to their licence texts (`OFL-*.txt`), so the game makes no network requests and works offline. Keep the licence files with the fonts whenever you ship them.

The font paths are relative to `web/`, so open `web/index.html` to play locally; opening `src/afterlap.html` directly shows fallback fonts.

## Before publishing

The game was first called "Rerun" and is now **Afterlap**. Before release, confirm the name is free in App Store Connect and run a trademark search on it.

Saved progress uses localStorage keys that still start with `rerun-`. That's on purpose, so existing progress isn't lost, and players never see it.
