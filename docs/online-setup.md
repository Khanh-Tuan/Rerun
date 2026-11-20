# Setting up online play (Supabase)

Online rooms need a small server. Afterlap uses a free Supabase project for that. You set it up once; it takes about 5 minutes and needs no installing.

## 1. Create the project

1. Go to https://supabase.com and sign up (GitHub sign-in works).
2. Click **New project**. Pick any name (for example `afterlap`), set a database password (save it in your password manager; the game never needs it), and choose the region closest to your players.
3. Wait about a minute for the project to finish setting up.

## 2. Create the rooms database

1. In the project, open **SQL Editor** (left sidebar) and click **New query**.
2. Open `supabase/setup.sql` from this repository, copy all of it, paste it into the editor, and click **Run**.
3. You should see "Success. No rows returned". Running it again later is safe.

## 3. Turn on anonymous sign-ins

Players don't make accounts. Each device signs in anonymously so the server can tell the two players apart.

1. Open **Authentication** > **Sign In / Providers** (on older dashboards: **Authentication** > **Providers**).
2. Turn on **Allow anonymous sign-ins** and save.

## 4. Copy the two connection values

1. Open **Project Settings** > **API** (or **Data API**).
2. Copy the **Project URL** (looks like `https://abcdefgh.supabase.co`).
3. Copy the **anon public** key (a long string starting with `eyJ`; on newer dashboards it may be the **publishable** key starting with `sb_publishable_`).

**Never** copy the `service_role` or **secret** key into the game. That key bypasses all the protections.

## 5. Put them in the game

In `src/afterlap.html`, find this line near the "Online: private rooms" comment:

```js
const ONLINE = { url: '', key: '' };
```

Fill in the two values, rebuild (`tools/build-web.ps1`), and the **Online** button on the title screen will work.

The anon key is designed to be public. It's safe in the game and on GitHub, because the database only allows what the functions in `setup.sql` allow: players can only read the room they're in, and can only change their own score and status.

## Good to know

- **Free tier:** Supabase pauses free projects after a week with no activity. Open the dashboard and click **Restore** if online play stops working after a quiet spell. A paid plan doesn't pause.
- **Timeouts** are set at the top of `supabase/setup.sql`: waiting rooms close after 15 minutes without a guest; a player who goes silent for 60 seconds is dropped (a run in progress ends at its last lap); empty rooms close; closed rooms are deleted after a day.
- **Seeing what's there:** **Table Editor** shows the `rooms` and `room_players` tables live.
