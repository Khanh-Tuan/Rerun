# Setting up leaderboards and accounts

This adds global, region and country leaderboards, optional player accounts (email code, no password), and cloud saves. It uses the same Supabase project as online rooms, so do [online-setup.md](online-setup.md) first.

## 1. Add the database part

1. Supabase dashboard > **SQL Editor** > **New query**.
2. Paste all of `supabase/leaderboard.sql` and click **Run**. You should see "Success. No rows returned". Running it again later is safe.

## 2. Make the sign-in emails show a 6-digit code

Players type a code instead of clicking a link, so sign-in works inside the iPhone app and any browser.

1. **Authentication** > **Emails** (older dashboards: **Email Templates**).
2. Open **Magic Link** and replace the body with:

   ```html
   <h2>Your Afterlap sign-in code</h2>
   <p>Type this code in the game:</p>
   <p style="font-size:28px;letter-spacing:6px"><b>{{ .Token }}</b></p>
   <p>If you didn't ask for it, you can ignore this email.</p>
   ```

3. Open **Change Email Address** and use the same body. This is the email a guest gets when they create an account.
4. Save both.

## 3. Send email to real players

Supabase's built-in email only sends to members of your Supabase team, and only about 2 emails an hour. It's fine for testing with your own address. For real players:

1. Sign up for an email service, for example [Resend](https://resend.com) (free tier). You need a domain you own, such as `afterlap.app`, and you add the DNS records it shows you.
2. In Supabase: **Authentication** > **Emails** > **SMTP Settings** > turn on **Custom SMTP** and fill in the details from Resend.
3. **Authentication** > **Rate Limits**: raise "emails per hour" to suit, for example 100.

## 4. Check these are on

- **Authentication** > **Sign In / Providers**: **Allow anonymous sign-ins** is on (guests), and **Email** is enabled.
- **Authentication** > **Sign In / Providers** > **Email**: **Confirm email** is on.

## How it works (short version)

- **Guests** play straight away. Every solo run is timed by the server, so a guest's best score is already verified before they sign up.
- **Creating an account** adds an email to the guest's existing player, so their scores, skins, stars and awards carry over automatically.
- **Signing in on another device** merges that device's progress with the online save. Skins and awards combine, the higher bests and stats win, and stars add up what each device earned or spent. Nothing is overwritten.
- **Scores** only rank if the server timed the run. The dot's speed is fixed by the speed curve, so a run of N laps takes a known minimum time; faster claims are rejected. Each run can be submitted once, starting runs is rate-limited, and scores far above everyone else's are held back as `flagged` for you to look at.
- **Ranks**: one entry per player (their best), ties go to whoever got there first, the boards show the top 1,000, 50 at a time, and every ranked player can see their own position even outside the top 1,000.
- **Country** is a guess from the player's connection or time zone, always confirmed by the player, and can be hidden. Hidden-country players only appear on the Global board. No GPS, no addresses, no IP addresses are stored.
- **Deleting an account** (in the game: Account > Delete account) removes the player's name, scores, runs and online save from the server.

## Looking after it

- **Table Editor** > `lb_scores` is the leaderboard; `lb_runs` has every timed run (`status` = ok / rejected / flagged).
- To review a flagged run: look it up in `lb_runs`. To remove a cheater's entry: delete their row from `lb_scores` (and their `ok` runs from `lb_runs` so it isn't re-posted).
- Regions: `lb_countries` maps each country to NA, EU, OC, ASIA, SEA, LATAM or MEA. The same table is near the top of the "Accounts, leaderboards and cloud save" section in `src/afterlap.html` (`COUNTRY_TABLE`). Keep the two in step.

## Test mode

For testing with several players without real email inboxes:

```sql
update lb_config set v = 'on' where k = 'test_mode';
```

While it's on, a guest can call `lb_dev_register()` to act like a registered player. Test players' scores are hidden from everyone once test mode is off. When testing is done:

```sql
select lb_test_cleanup();
```

That deletes every test player and everything they made, and turns test mode off.
