-- Afterlap leaderboards, player accounts and cloud saves.
-- Run this once in Supabase (Dashboard > SQL Editor > New query > paste > Run), AFTER setup.sql.
-- Safe to run again: it replaces the functions and only creates tables that don't exist yet.
--
-- How it fits together
--   * Every player is signed in to Supabase. Guests are anonymous users; "creating an account" adds an email
--     to that same user, so the player ID, verified scores and progress all stay put.
--   * A score only counts if the server timed the run: lb_start_run() when a run begins, lb_finish_run() when
--     it ends. The dot's speed is fixed by the speed curve, so N laps take a known minimum time; anything
--     faster is rejected. Each run can be finished once. Extreme outliers are held back for review.
--   * Only registered players with a profile (name + country) appear on the boards.
--   * Row level security is on for every table and there are no table policies: clients can't read or write
--     tables directly. Everything goes through the functions below, which check who is calling.
--
-- Settings live in lb_config:
--   test_mode  'off' (default) | 'on'. While on, lb_dev_register() lets an anonymous test player act like a
--              registered one, so several accounts can be tested without real email inboxes.
--              Turn it off and remove test players with:   select lb_test_cleanup();

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------------------------------------------
-- Tables

create table if not exists public.lb_config (k text primary key, v text not null);
insert into public.lb_config (k, v) values ('test_mode', 'off') on conflict (k) do nothing;

-- Every country belongs to exactly one region. The same table is in the game (COUNTRY_TABLE); keep them in step.
create table if not exists public.lb_countries (code text primary key check (code ~ '^[A-Z]{2}$'), region text not null);
insert into public.lb_countries (code, region)
select c, split_part(part, ':', 1)
  from unnest(string_to_array(
    'NA:US CA MX BM GL PM UM|LATAM:AG AI AR AW BB BL BO BQ BR BS BZ CL CO CR CU CW DM DO EC FK GD GF GP GS GT GY HN HT JM KN KY LC MF MQ MS NI PA PE PR PY SR SV SX TC TT UY VC VE VG VI|EU:AD AL AM AT AX AZ BA BE BG BV BY CH CY CZ DE DK EE ES FI FO FR GB GE GG GI GR HR HU IE IM IS IT JE LI LT LU LV MC MD ME MK MT NL NO PL PT RO RS RU SE SI SJ SK SM TR UA VA XK|MEA:AE BH DZ AO BJ BW BF BI CV CM CF TD KM CG CD CI DJ EG EH ER ET GA GM GH GN GQ GW IL IQ IR JO KE KW LB LR LS LY MA MG ML MR MU MW MZ NA NE NG OM PS QA RE RW SA SC SD SH SL SN SO SS ST SY SZ TF TG TN TZ UG YE YT ZA ZM ZW|ASIA:AF BD BT CN HK IN IO JP KG KP KR KZ LK MN MO MV NP PK TJ TM TW UZ|SEA:BN ID KH LA MM MY PH SG TH TL VN|OC:AQ AS AU CC CK CX FJ FM GU HM KI MH MP NC NF NR NU NZ PF PG PN PW SB TK TO TV VU WF WS',
    '|')) part,
       unnest(string_to_array(split_part(part, ':', 2), ' ')) c
on conflict (code) do update set region = excluded.region;

-- Public identity. No email, no location beyond the country the player chose.
create table if not exists public.lb_profiles (
  player_id     uuid primary key references auth.users (id) on delete cascade,
  display_name  text not null check (char_length(display_name) between 3 and 16),
  name_key      text not null unique,                       -- lower-case name: names are unique, ignoring case
  country       text not null references public.lb_countries (code),
  show_country  boolean not null default true,              -- false: no flag, and not on region/country boards
  skin          text check (skin is null or skin ~ '^[a-z0-9_]{1,24}$'),
  created_at    timestamptz not null default now(),
  last_seen     timestamptz not null default now()
);

-- One row per ranked player: their best verified score. Boards are read straight from here.
create table if not exists public.lb_scores (
  player_id    uuid primary key references public.lb_profiles (player_id) on delete cascade,
  score        int not null check (score >= 0),
  achieved_at  timestamptz not null,                        -- ties: whoever got there first ranks higher
  run_id       uuid,
  region       text,                                        -- null when the player hides their country
  country      text,
  prev_score   int,
  improved_at  timestamptz,
  created_at   timestamptz not null default now(),
  is_test      boolean not null default false
);
create index if not exists lb_scores_global  on public.lb_scores (score desc, achieved_at asc);
create index if not exists lb_scores_region  on public.lb_scores (region, score desc, achieved_at asc);
create index if not exists lb_scores_country on public.lb_scores (country, score desc, achieved_at asc);

-- Timed runs. taps = lane-switch times (ms from the start), kept for audits and future replay checks.
create table if not exists public.lb_runs (
  id           uuid primary key default gen_random_uuid(),
  player_id    uuid not null references auth.users (id) on delete cascade,
  started_at   timestamptz not null,
  finished_at  timestamptz,
  score        int,
  close_calls  int,
  taps         text,
  status       text not null default 'open' check (status in ('open', 'ok', 'rejected', 'flagged')),
  reason       text
);
create index if not exists lb_runs_player on public.lb_runs (player_id, started_at desc);
create index if not exists lb_runs_best   on public.lb_runs (player_id, score desc, finished_at asc) where status = 'ok';

-- Cloud save: the whole local progress as one JSON document, with a version for safe merging.
create table if not exists public.lb_saves (
  player_id   uuid primary key references auth.users (id) on delete cascade,
  data        jsonb not null,
  version     int not null default 1,
  updated_at  timestamptz not null default now()
);

-- A guest who signs in to an EXISTING account hands their verified runs over with a one-time token.
create table if not exists public.lb_transfers (
  token        text primary key,
  from_player  uuid not null references auth.users (id) on delete cascade,
  created_at   timestamptz not null default now()
);

create table if not exists public.lb_test_players (player_id uuid primary key references auth.users (id) on delete cascade);

alter table public.lb_config       enable row level security;
alter table public.lb_countries    enable row level security;
alter table public.lb_profiles     enable row level security;
alter table public.lb_scores       enable row level security;
alter table public.lb_runs         enable row level security;
alter table public.lb_saves        enable row level security;
alter table public.lb_transfers    enable row level security;
alter table public.lb_test_players enable row level security;
revoke all on public.lb_config, public.lb_countries, public.lb_profiles, public.lb_scores, public.lb_runs,
  public.lb_saves, public.lb_transfers, public.lb_test_players from anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- Helpers

create or replace function public.lb_test_mode() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select v = 'on' from lb_config where k = 'test_mode'), false);
$$;

-- Registered = has an email on their sign-in (or is a test player while test mode is on).
create or replace function public.lb_registered(p uuid) returns boolean
language sql stable security definer set search_path = public, auth as $$
  select exists (select 1 from auth.users u where u.id = p and u.email is not null and not coalesce(u.is_anonymous, false))
      or (lb_test_mode() and exists (select 1 from lb_test_players t where t.player_id = p));
$$;

-- The game's speed curve (speedAt in the game) and the shortest possible time for N laps.
create or replace function public.lb_speed(p_lap int) returns double precision
language sql immutable as $$
  select case when p_lap <= 10 then 1 + 0.025 * (p_lap - 1)
              else least(1.78, 1.225 + 0.555 * (1 - exp(-(p_lap - 10) / 35.0))) end;
$$;
create or replace function public.lb_min_seconds(p_laps int) returns double precision
language sql immutable as $$
  select coalesce(sum(4.6 / lb_speed(k)), 0) from generate_series(1, greatest(least(p_laps, 100000), 0)) k;
$$;

-- Rank a score would have on a board (ties go to whoever got there first). Null region/country = that filter off.
create or replace function public.lb_rank(p_score int, p_at timestamptz, p_region text, p_country text) returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int + 1 from lb_scores s
   where (s.score > p_score or (s.score = p_score and s.achieved_at < p_at))
     and (p_region is null or s.region = p_region)
     and (p_country is null or s.country = p_country)
     and (not s.is_test or lb_test_mode());
$$;
create or replace function public.lb_total(p_region text, p_country text) returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from lb_scores s
   where (p_region is null or s.region = p_region) and (p_country is null or s.country = p_country)
     and (not s.is_test or lb_test_mode());
$$;

-- Ranks for one ranked player on all three boards.
create or replace function public.lb_ranks_of(p uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when s.player_id is null then null else jsonb_build_object(
    'score', s.score, 'at', s.achieved_at,
    'global', lb_rank(s.score, s.achieved_at, null, null),          'global_total', lb_total(null, null),
    'region', case when s.region is not null then lb_rank(s.score, s.achieved_at, s.region, null) end,
    'region_total', case when s.region is not null then lb_total(s.region, null) end,
    'country', case when s.country is not null then lb_rank(s.score, s.achieved_at, null, s.country) end,
    'country_total', case when s.country is not null then lb_total(null, s.country) end,
    'region_code', s.region, 'country_code', s.country) end
  from (select 1) one left join lb_scores s on s.player_id = p;
$$;

-- Put a player's best verified run on the boards (or improve it). Needs a profile. Returns true if it changed.
create or replace function public.lb_post_best(p uuid) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  pr lb_profiles;
  r  lb_runs;
  s  lb_scores;
begin
  select * into pr from lb_profiles where player_id = p;
  if not found then return false; end if;
  select * into r from lb_runs where player_id = p and status = 'ok' order by score desc, finished_at asc limit 1;
  if not found then return false; end if;
  select * into s from lb_scores where player_id = p;
  if found and s.score >= r.score then return false; end if;
  insert into lb_scores (player_id, score, achieved_at, run_id, region, country, is_test)
  values (p, r.score, r.finished_at, r.id,
          case when pr.show_country then (select region from lb_countries where code = pr.country) end,
          case when pr.show_country then pr.country end,
          exists (select 1 from lb_test_players where player_id = p))
  on conflict (player_id) do update set
    prev_score = lb_scores.score, improved_at = now(),
    score = excluded.score, achieved_at = excluded.achieved_at, run_id = excluded.run_id;
  return true;
end $$;

-- Country from the visitor's IP, as reported by Supabase's CDN (Cloudflare). Read, never stored.
create or replace function public.lb_ip_country() returns text
language sql stable security definer set search_path = public as $$
  select code from lb_countries
   where code = upper(coalesce(nullif(current_setting('request.headers', true), '')::json ->> 'cf-ipcountry', ''));
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Account

-- Everything the game needs to know about the caller, in one call.
create or replace function public.lb_me() returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare
  v_uid uuid := auth.uid();
  u auth.users;
  pr lb_profiles;
  v_best lb_runs;
  v_mail text;
begin
  if v_uid is null then raise exception 'not_signed_in'; end if;
  select * into u from auth.users where id = v_uid;
  select * into pr from lb_profiles where player_id = v_uid;
  if found then update lb_profiles set last_seen = now() where player_id = v_uid; end if;
  select * into v_best from lb_runs where player_id = v_uid and status = 'ok' order by score desc, finished_at asc limit 1;
  -- masked email, only ever shown to its owner: t•••@gmail.com
  if u.email is not null then v_mail := left(u.email, 1) || '•••@' || split_part(u.email, '@', 2); end if;
  return jsonb_build_object(
    'id', v_uid,
    'registered', lb_registered(v_uid),
    'anonymous', coalesce(u.is_anonymous, false) and u.email is null,
    'email', v_mail,
    'test', exists (select 1 from lb_test_players where player_id = v_uid),
    'profile', case when pr.player_id is null then null else jsonb_build_object(
        'name', pr.display_name, 'country', pr.country, 'show_country', pr.show_country, 'skin', pr.skin,
        'region', (select region from lb_countries where code = pr.country), 'created_at', pr.created_at) end,
    'best', case when v_best.id is null then null else jsonb_build_object('score', v_best.score, 'at', v_best.finished_at) end,
    'ranks', lb_ranks_of(v_uid),
    'ip_country', lb_ip_country(),
    'now', now());
end $$;

-- Create or edit the public profile. Registered players only. Posting the best verified run happens here too,
-- so "claim my rank" is simply: register, then save a profile.
create or replace function public.lb_set_profile(p_name text, p_country text, p_show boolean, p_skin text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_name text := regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g');
  v_country text := upper(coalesce(p_country, ''));
  v_region text;
begin
  if v_uid is null then raise exception 'not_signed_in'; end if;
  if not lb_registered(v_uid) then return jsonb_build_object('error', 'not_registered'); end if;
  if char_length(v_name) < 3 or char_length(v_name) > 16 then return jsonb_build_object('error', 'name_length'); end if;
  if v_name !~ '^[[:alnum:]][[:alnum:] _.-]*[[:alnum:]]$' then return jsonb_build_object('error', 'name_chars'); end if;
  if lower(v_name) ~ '(admin|moderator|official|afterlap|support|staff|fuck|shit|cunt|nigg|fag|rape|nazi|hitler)'
    then return jsonb_build_object('error', 'name_blocked'); end if;
  select region into v_region from lb_countries where code = v_country;
  if v_region is null then return jsonb_build_object('error', 'bad_country'); end if;
  if exists (select 1 from lb_profiles where name_key = lower(v_name) and player_id <> v_uid) then
    return jsonb_build_object('error', 'name_taken');
  end if;
  insert into lb_profiles (player_id, display_name, name_key, country, show_country, skin)
  values (v_uid, v_name, lower(v_name), v_country, coalesce(p_show, true), nullif(p_skin, ''))
  on conflict (player_id) do update set
    display_name = excluded.display_name, name_key = excluded.name_key, country = excluded.country,
    show_country = excluded.show_country, skin = coalesce(excluded.skin, lb_profiles.skin), last_seen = now();
  -- moving country (or hiding it) moves the existing board entry too
  update lb_scores set region = case when coalesce(p_show, true) then v_region end,
                       country = case when coalesce(p_show, true) then v_country end
   where player_id = v_uid;
  perform lb_post_best(v_uid);
  return lb_me();
exception when unique_violation then
  return jsonb_build_object('error', 'name_taken');
end $$;

-- Equipped skin shown next to your name (cosmetic only).
create or replace function public.lb_set_skin(p_skin text) returns void
language sql security definer set search_path = public as $$
  update lb_profiles set skin = p_skin where player_id = auth.uid() and p_skin ~ '^[a-z0-9_]{1,24}$';
$$;

-- Claim: put the best verified run on the boards. Safe to call any number of times (one row per player).
create or replace function public.lb_claim() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_signed_in'; end if;
  if not lb_registered(v_uid) then return jsonb_build_object('error', 'not_registered'); end if;
  if not exists (select 1 from lb_profiles where player_id = v_uid) then return jsonb_build_object('error', 'no_profile'); end if;
  perform lb_post_best(v_uid);
  return jsonb_build_object('ok', true, 'ranks', lb_ranks_of(v_uid));
end $$;

-- Guest about to sign in to an existing account: get a one-time token for their verified runs.
create or replace function public.lb_make_transfer() returns text
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_tok text;
begin
  if v_uid is null then raise exception 'not_signed_in'; end if;
  if lb_registered(v_uid) then return null; end if;
  if not exists (select 1 from lb_runs where player_id = v_uid and status = 'ok') then return null; end if;
  delete from lb_transfers where from_player = v_uid or created_at < now() - interval '1 day';
  v_tok := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');   -- 244 random bits
  insert into lb_transfers (token, from_player) values (v_tok, v_uid);
  return v_tok;
end $$;

-- Signed in to the account: move the guest's verified runs over (once), then post the best.
create or replace function public.lb_redeem_transfer(p_token text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); t lb_transfers; v_n int;
begin
  if v_uid is null then raise exception 'not_signed_in'; end if;
  if not lb_registered(v_uid) then return jsonb_build_object('error', 'not_registered'); end if;
  delete from lb_transfers where token = p_token and created_at > now() - interval '1 day' returning * into t;
  if t.token is null then return jsonb_build_object('error', 'bad_token'); end if;
  if t.from_player = v_uid or lb_registered(t.from_player) then return jsonb_build_object('error', 'bad_token'); end if;
  update lb_runs set player_id = v_uid where player_id = t.from_player and status = 'ok';
  get diagnostics v_n = row_count;
  perform lb_post_best(v_uid);
  return jsonb_build_object('ok', true, 'moved', v_n);
end $$;

-- Delete the account and everything stored for it (App Store rule: accounts must be deletable in the app).
create or replace function public.lb_delete_account() returns void
language plpgsql security definer set search_path = public, auth as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  delete from auth.users where id = auth.uid();     -- profile, scores, runs and save go with it (on delete cascade)
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Score validation

-- A run is starting. p_late_ms: how long after the run actually began this call was made (capped at 1.5 s).
create or replace function public.lb_start_run(p_late_ms int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
begin
  if v_uid is null then raise exception 'not_signed_in'; end if;
  -- rate limits: one run start per 1.5 s, 600 a day
  if exists (select 1 from lb_runs where player_id = v_uid and started_at > now() - interval '1.5 seconds') then
    return jsonb_build_object('error', 'too_fast');
  end if;
  if (select count(*) from lb_runs where player_id = v_uid and started_at > now() - interval '1 day') >= 600 then
    return jsonb_build_object('error', 'rate_limited');
  end if;
  insert into lb_runs (player_id, started_at)
  values (v_uid, now() - make_interval(secs => least(greatest(coalesce(p_late_ms, 0), 0), 1500) / 1000.0))
  returning id into v_id;
  update lb_profiles set last_seen = now() where player_id = v_uid;
  -- now and then: drop old runs nobody needs (each player's best verified run is always kept)
  if random() < 0.02 then
    delete from lb_runs r where r.started_at < now() - interval '2 days'
       and (r.status <> 'ok' or exists (select 1 from lb_runs b where b.player_id = r.player_id and b.status = 'ok'
              and (b.score > r.score or (b.score = r.score and b.finished_at < r.finished_at))));
  end if;
  return jsonb_build_object('run', v_id);
end $$;

-- The run ended. Checks it, keeps it, posts a new best for ranked players, and says where the score stands.
-- p_country: the game's guess of the player's country, used only to preview region/country ranks for guests.
create or replace function public.lb_finish_run(p_run uuid, p_score int, p_close int, p_taps text, p_country text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  r lb_runs;
  v_elapsed double precision;
  v_need double precision;
  v_status text := 'ok';
  v_reason text;
  v_top int;
  v_prev lb_runs;
  v_before jsonb;
  v_posted boolean := false;
  v_reg boolean;
  v_country text;
  v_region text;
  v_best int;
begin
  if v_uid is null then raise exception 'not_signed_in'; end if;
  select * into r from lb_runs where id = p_run for update;
  if not found or r.player_id <> v_uid then return jsonb_build_object('error', 'not_found'); end if;
  if r.status <> 'open' then return jsonb_build_object('error', 'already_finished'); end if;

  v_elapsed := extract(epoch from (now() - r.started_at));
  v_need := lb_min_seconds(coalesce(p_score, 0));
  if p_score is null or p_score < 0 or p_score > 100000 then
    v_status := 'rejected'; v_reason := 'bad_score';
  elsif v_elapsed > 6 * 3600 then
    v_status := 'rejected'; v_reason := 'too_old';
  elsif v_elapsed < v_need * 0.97 - 2.0 then
    v_status := 'rejected'; v_reason := 'too_fast';                  -- faster than the dot can physically go
  elsif coalesce(length(p_taps), 0) > 200000 then
    v_status := 'rejected'; v_reason := 'bad_taps';
  else
    -- way above everyone else: hold it back for a human to look at
    select max(score) into v_top from lb_scores where not is_test;
    if p_score > greatest(200, coalesce(v_top, 0) * 2) then v_status := 'flagged'; v_reason := 'outlier'; end if;
  end if;

  select * into v_prev from lb_runs where player_id = v_uid and status = 'ok' order by score desc, finished_at asc limit 1;
  v_before := lb_ranks_of(v_uid);
  update lb_runs set finished_at = now(), score = p_score, close_calls = least(greatest(coalesce(p_close, 0), 0), 100000),
                     taps = left(p_taps, 200000), status = v_status, reason = v_reason
   where id = p_run;
  v_reg := lb_registered(v_uid);
  if v_status = 'ok' and v_reg then v_posted := lb_post_best(v_uid); end if;
  v_best := greatest(coalesce(v_prev.score, -1), case when v_status = 'ok' then p_score else -1 end);

  -- where would this best land? (for guests: what they'd get by claiming it)
  select pr.country into v_country from lb_profiles pr where pr.player_id = v_uid;
  v_country := coalesce(v_country, (select code from lb_countries where code = upper(coalesce(p_country, ''))));
  select region into v_region from lb_countries where code = v_country;

  return jsonb_build_object(
    'status', v_status, 'reason', v_reason, 'score', p_score,
    'best', case when v_best >= 0 then v_best end,
    'new_best', v_status = 'ok' and p_score > coalesce(v_prev.score, -1),
    'registered', v_reg, 'posted', v_posted,
    'ranks_before', v_before, 'ranks', lb_ranks_of(v_uid),
    'preview', case when v_best >= 0 then jsonb_build_object(
        'global', lb_rank(v_best, now(), null, null),
        'region', case when v_region is not null then lb_rank(v_best, now(), v_region, null) end,
        'country', case when v_country is not null then lb_rank(v_best, now(), null, v_country) end,
        'region_code', v_region, 'country_code', v_country) end);
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Leaderboards

-- One page of a board. p_scope: 'global' | 'region' | 'country'; p_key: region or country code.
-- Pages of up to 50, never past rank 1,000. Also returns the caller's own rank on this board.
create or replace function public.lb_board(p_scope text, p_key text, p_offset int, p_limit int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_region text := case when p_scope = 'region' then upper(p_key) end;
  v_country text := case when p_scope = 'country' then upper(p_key) end;
  v_off int := least(greatest(coalesce(p_offset, 0), 0), 1000);
  v_lim int := least(greatest(coalesce(p_limit, 50), 1), 50);
  v_rows jsonb;
  me lb_scores;
  v_tm boolean := lb_test_mode();
begin
  if v_uid is null then raise exception 'not_signed_in'; end if;
  if p_scope not in ('global', 'region', 'country') then return jsonb_build_object('error', 'bad_scope'); end if;
  v_lim := least(v_lim, 1000 - v_off);
  -- cut the page out first (uses the index), then number it from the page's starting rank
  select coalesce(jsonb_agg(x order by x.rank), '[]'::jsonb) into v_rows from (
    select v_off + row_number() over (order by p.score desc, p.achieved_at asc) as rank,
           p.name, p.country, p.score, p.skin, p.online, p."new", p.improved, p.me
      from (
        select pr.display_name as name, s.country, s.score, s.achieved_at, pr.skin,
               (pr.last_seen > now() - interval '3 minutes') as online,
               (s.created_at > now() - interval '1 day') as "new",
               (s.prev_score is not null and s.improved_at > now() - interval '1 day') as improved,
               (s.player_id = v_uid) as me
          from lb_scores s join lb_profiles pr on pr.player_id = s.player_id
         where (v_region is null or s.region = v_region) and (v_country is null or s.country = v_country)
           and (not s.is_test or v_tm)
         order by s.score desc, s.achieved_at asc
         offset v_off limit v_lim) p) x;
  select * into me from lb_scores where player_id = v_uid;
  return jsonb_build_object(
    'rows', v_rows,
    'total', lb_total(v_region, v_country),
    'offset', v_off,
    'me', case when me.player_id is not null
                and (v_region is null or me.region = v_region) and (v_country is null or me.country = v_country)
               then lb_rank(me.score, me.achieved_at, v_region, v_country) end,
    'now', now());
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Cloud save

create or replace function public.lb_get_save() returns jsonb
language plpgsql security definer set search_path = public as $$
declare s lb_saves;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  if not lb_registered(auth.uid()) then return jsonb_build_object('error', 'not_registered'); end if;
  select * into s from lb_saves where player_id = auth.uid();
  if not found then return jsonb_build_object('version', 0); end if;
  return jsonb_build_object('data', s.data, 'version', s.version, 'updated_at', s.updated_at);
end $$;

-- Save only if nobody else saved since you last read it (p_base = the version you started from).
-- Otherwise you get the newer save back, merge, and try again.
create or replace function public.lb_put_save(p_data jsonb, p_base int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s lb_saves; v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_signed_in'; end if;
  if not lb_registered(v_uid) then return jsonb_build_object('error', 'not_registered'); end if;
  if p_data is null or jsonb_typeof(p_data) <> 'object' then return jsonb_build_object('error', 'bad_data'); end if;
  if octet_length(p_data::text) > 262144 then return jsonb_build_object('error', 'too_big'); end if;
  select * into s from lb_saves where player_id = v_uid for update;
  if found and s.version <> coalesce(p_base, -1) then
    return jsonb_build_object('conflict', true, 'data', s.data, 'version', s.version);
  end if;
  insert into lb_saves (player_id, data, version, updated_at) values (v_uid, p_data, 1, now())
  on conflict (player_id) do update set data = excluded.data, version = lb_saves.version + 1, updated_at = now()
  returning * into s;
  return jsonb_build_object('ok', true, 'version', s.version, 'updated_at', s.updated_at);
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Test mode (only while lb_config.test_mode = 'on')

create or replace function public.lb_dev_register() returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  if not lb_test_mode() then return jsonb_build_object('error', 'test_mode_off'); end if;
  insert into lb_test_players (player_id) values (auth.uid()) on conflict do nothing;
  return lb_me();
end $$;

-- Run from the SQL Editor when testing is done: deletes every test player and everything they made,
-- and turns test mode off.
create or replace function public.lb_test_cleanup() returns int
language plpgsql security definer set search_path = public, auth as $$
declare v_n int;
begin
  delete from auth.users where id in (select player_id from lb_test_players);
  get diagnostics v_n = row_count;
  delete from lb_test_players;
  update lb_config set v = 'off' where k = 'test_mode';
  return v_n;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Who may call what

revoke all on function
  public.lb_test_mode(), public.lb_registered(uuid), public.lb_speed(int), public.lb_min_seconds(int),
  public.lb_rank(int, timestamptz, text, text), public.lb_total(text, text), public.lb_ranks_of(uuid),
  public.lb_post_best(uuid), public.lb_ip_country(), public.lb_test_cleanup(),
  public.lb_me(), public.lb_set_profile(text, text, boolean, text), public.lb_set_skin(text), public.lb_claim(),
  public.lb_make_transfer(), public.lb_redeem_transfer(text), public.lb_delete_account(),
  public.lb_start_run(int), public.lb_finish_run(uuid, int, int, text, text),
  public.lb_board(text, text, int, int), public.lb_get_save(), public.lb_put_save(jsonb, int), public.lb_dev_register()
from public, anon, authenticated;
grant execute on function
  public.lb_me(), public.lb_set_profile(text, text, boolean, text), public.lb_set_skin(text), public.lb_claim(),
  public.lb_make_transfer(), public.lb_redeem_transfer(text), public.lb_delete_account(),
  public.lb_start_run(int), public.lb_finish_run(uuid, int, int, text, text),
  public.lb_board(text, text, int, int), public.lb_get_save(), public.lb_put_save(jsonb, int), public.lb_dev_register()
to authenticated;
