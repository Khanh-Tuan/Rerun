-- Afterlap online rooms: run this once in your Supabase project (Dashboard > SQL Editor > New query > paste > Run).
-- Safe to run again: it replaces the functions and only creates tables that don't exist yet.
--
-- How it's secured
--   * Every player signs in anonymously (Supabase "Anonymous sign-ins" must be ON), so each one has an auth.uid().
--   * Row level security is on for both tables. Players can READ only the room they're in, and can't WRITE
--     anything directly. Every change goes through the functions below, which check who is calling.
--   * A player can only ever change their own row, and scores are sanity-checked against the time played.
--
-- Timeouts (change them here)
--   waiting room with no guest ............ 15 minutes, then closed
--   player with no heartbeat .............. 60 seconds: a run in progress ends at its last reported lap,
--                                           and the player is shown as "left" (they can come back)
--   whole room with no heartbeat .......... 10 minutes, then closed
--   closed rooms are deleted .............. after 1 day

create extension if not exists pgcrypto;

create table if not exists public.rooms (
  id          uuid primary key default gen_random_uuid(),
  code        text not null check (code ~ '^[0-9]{5}$'),
  host_id     uuid not null,
  guest_id    uuid,
  status      text not null default 'waiting' check (status in ('waiting', 'ready', 'playing', 'finished', 'closed')),
  round       int  not null default 0,
  started_at  timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
-- A code can only belong to one open room at a time.
create unique index if not exists rooms_open_code on public.rooms (code) where status <> 'closed';

create table if not exists public.room_players (
  room_id        uuid not null references public.rooms (id) on delete cascade,
  player_id      uuid not null,
  role           text not null check (role in ('host', 'guest')),
  display_name   text not null check (char_length(display_name) between 1 and 16),
  round          int  not null default 0,
  current_score  int  not null default 0,
  best_score     int  not null default 0,
  close_calls    int  not null default 0,
  wins           int  not null default 0,
  player_status  text not null default 'lobby' check (player_status in ('lobby', 'ready', 'playing', 'eliminated', 'left')),
  last_seen      timestamptz not null default now(),
  primary key (room_id, player_id)
);

alter table public.rooms enable row level security;
alter table public.room_players enable row level security;

-- Membership check used by the read policies (security definer so the policy doesn't recurse).
create or replace function public.is_room_member(p_room uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from room_players where room_id = p_room and player_id = auth.uid());
$$;

drop policy if exists "members read room" on public.rooms;
create policy "members read room" on public.rooms for select to authenticated using (public.is_room_member(id));
drop policy if exists "members read players" on public.room_players;
create policy "members read players" on public.room_players for select to authenticated using (public.is_room_member(room_id));

-- Live updates: clients subscribe to changes on these two tables (still filtered by the policies above).
do $$ begin
  alter publication supabase_realtime add table public.rooms;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.room_players;
exception when duplicate_object then null; end $$;
alter table public.room_players replica identity full;

-- ---------------------------------------------------------------------------------------------------------------
-- Housekeeping: called from the other functions, so no scheduler is needed.
create or replace function public.cleanup_rooms() returns void
language plpgsql security definer set search_path = public as $$
begin
  -- players who stopped sending heartbeats: their run ends where it was, and they're treated as gone
  update room_players set player_status = 'eliminated'
   where player_status = 'playing' and last_seen < now() - interval '60 seconds';
  update room_players set player_status = 'left'
   where player_status in ('lobby', 'ready', 'eliminated') and last_seen < now() - interval '60 seconds';
  perform finish_if_done(id) from rooms where status = 'playing';
  -- abandoned waiting rooms, rooms nobody is in any more, and rooms with no heartbeat at all
  update rooms r set status = 'closed', updated_at = now()
   where status <> 'closed' and (
         (status = 'waiting' and guest_id is null and created_at < now() - interval '15 minutes')
      or not exists (select 1 from room_players p where p.room_id = r.id and p.player_status <> 'left')
      or not exists (select 1 from room_players p where p.room_id = r.id and p.last_seen > now() - interval '10 minutes'));
  delete from rooms where status = 'closed' and updated_at < now() - interval '1 day';
end $$;

create or replace function public.clean_name(p_name text) returns text
language sql immutable as $$
  select coalesce(nullif(left(regexp_replace(btrim(coalesce(p_name, '')), '[[:cntrl:]]', '', 'g'), 16), ''), 'Player');
$$;

-- Everything the client needs about one room, in one call.
create or replace function public.room_state(p_room uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'room', to_jsonb(r) - 'host_id' - 'guest_id',
    'me', auth.uid(),
    'now', now(),
    'players', coalesce((select jsonb_agg(to_jsonb(p) order by p.role desc) from room_players p where p.room_id = r.id), '[]'::jsonb))
  from rooms r where r.id = p_room and public.is_room_member(r.id);
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Create a room with a fresh 5-digit code. Leaves any other room the caller was in.
create or replace function public.create_room(p_name text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_room uuid;
  v_code text;
  i int := 0;
begin
  if v_uid is null then raise exception 'not_signed_in'; end if;
  perform cleanup_rooms();
  update room_players set player_status = 'left', last_seen = now() where player_id = v_uid and player_status <> 'left';
  perform cleanup_rooms();
  loop
    i := i + 1;
    v_code := lpad((10000 + floor(random() * 90000))::int::text, 5, '0');
    begin
      insert into rooms (code, host_id) values (v_code, v_uid) returning id into v_room;
      exit;
    exception when unique_violation then
      if i > 40 then raise exception 'no_codes'; end if;
    end;
  end loop;
  insert into room_players (room_id, player_id, role, display_name) values (v_room, v_uid, 'host', clean_name(p_name));
  return room_state(v_room);
end $$;

-- Look a code up before joining: tells the joiner whose room it is, or why they can't join.
create or replace function public.find_room(p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  r rooms;
  v_host text;
begin
  if v_uid is null then raise exception 'not_signed_in'; end if;
  if p_code !~ '^[0-9]{5}$' then return jsonb_build_object('error', 'bad_code'); end if;
  perform cleanup_rooms();
  select * into r from rooms where code = p_code and status <> 'closed';
  if not found then
    if exists (select 1 from rooms where code = p_code) then return jsonb_build_object('error', 'expired'); end if;
    return jsonb_build_object('error', 'not_found');
  end if;
  select display_name into v_host from room_players where room_id = r.id and role = 'host';
  if r.host_id = v_uid then return jsonb_build_object('error', 'own_room'); end if;
  if r.guest_id = v_uid then return jsonb_build_object('room', r.id, 'host', v_host, 'rejoin', true); end if;
  if not exists (select 1 from room_players where room_id = r.id and role = 'host' and player_status <> 'left') then
    return jsonb_build_object('error', 'host_left');
  end if;
  if r.guest_id is not null then
    if r.status in ('playing') then return jsonb_build_object('error', 'started'); end if;
    return jsonb_build_object('error', 'full');
  end if;
  return jsonb_build_object('room', r.id, 'host', v_host);
end $$;

-- Take the free seat. The row lock means two people joining at the same moment can't both get it.
create or replace function public.join_room(p_code text, p_name text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  r rooms;
begin
  if v_uid is null then raise exception 'not_signed_in'; end if;
  perform cleanup_rooms();
  select * into r from rooms where code = p_code and status <> 'closed' for update;
  if not found then return jsonb_build_object('error', 'not_found'); end if;
  if r.host_id = v_uid then return jsonb_build_object('error', 'own_room'); end if;
  if r.guest_id = v_uid then
    -- coming back to a room you were already in (refresh, reopen, lost connection)
    update room_players set last_seen = now(),
           player_status = case when player_status = 'left' then 'lobby' else player_status end
     where room_id = r.id and player_id = v_uid;
    return room_state(r.id);
  end if;
  if r.guest_id is not null then return jsonb_build_object('error', case when r.status = 'playing' then 'started' else 'full' end); end if;
  if not exists (select 1 from room_players where room_id = r.id and role = 'host' and player_status <> 'left') then
    return jsonb_build_object('error', 'host_left');
  end if;
  update room_players set player_status = 'left' where player_id = v_uid and player_status <> 'left';
  update rooms set guest_id = v_uid, status = 'ready', updated_at = now() where id = r.id;
  insert into room_players (room_id, player_id, role, display_name, player_status)
  values (r.id, v_uid, 'guest', clean_name(p_name), 'ready');
  return room_state(r.id);
end $$;

-- Rejoin after a refresh: returns the room if the caller is still a member of an open one.
create or replace function public.my_room() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_room uuid;
begin
  perform cleanup_rooms();
  select p.room_id into v_room from room_players p join rooms r on r.id = p.room_id
   where p.player_id = auth.uid() and r.status <> 'closed'
   order by r.updated_at desc limit 1;
  if v_room is null then return null; end if;
  update room_players set last_seen = now(),
         player_status = case when player_status = 'left' then 'lobby' else player_status end
   where room_id = v_room and player_id = auth.uid();
  return room_state(v_room);
end $$;

-- "I'm ready" (host's Start, guest's confirm, and both players' Play again). When both are ready, a round starts.
create or replace function public.set_ready(p_room uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  r rooms;
begin
  select * into r from rooms where id = p_room and status <> 'closed' for update;
  if not found or not is_room_member(p_room) then return jsonb_build_object('error', 'not_found'); end if;
  if r.status = 'playing' then return room_state(p_room); end if;
  update room_players set player_status = 'ready', last_seen = now() where room_id = p_room and player_id = v_uid;
  if (select count(*) from room_players where room_id = p_room and player_status = 'ready') = 2 then
    update rooms set status = 'playing', round = round + 1, started_at = now() + interval '3 seconds', updated_at = now() where id = p_room;
    update room_players set player_status = 'playing', round = r.round + 1, current_score = 0, close_calls = 0, last_seen = now()
     where room_id = p_room;
  end if;
  return room_state(p_room);
end $$;

-- Live score from the caller's own run. Only their own row, only for the current round, only going up,
-- and never more laps than could have been driven in the time since the round started.
create or replace function public.report_run(p_room uuid, p_round int, p_score int, p_close int, p_dead boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  r rooms;
  me room_players;
  v_cap int;
begin
  select * into r from rooms where id = p_room for update;
  select * into me from room_players where room_id = p_room and player_id = v_uid;
  if r.id is null or me.player_id is null then return jsonb_build_object('error', 'not_found'); end if;
  if r.status <> 'playing' or p_round <> r.round or me.round <> r.round or me.player_status not in ('playing') then
    update room_players set last_seen = now() where room_id = p_room and player_id = v_uid;
    return jsonb_build_object('ok', false);
  end if;
  -- fastest lap is 2.9 s, so this is a generous ceiling
  v_cap := greatest(0, floor(extract(epoch from (now() - r.started_at)) / 2.5)::int + 1);
  update room_players set
      current_score = least(greatest(current_score, coalesce(p_score, 0)), v_cap),
      best_score    = greatest(best_score, least(greatest(current_score, coalesce(p_score, 0)), v_cap)),
      close_calls   = least(greatest(close_calls, coalesce(p_close, 0)), 9999),
      player_status = case when p_dead then 'eliminated' else player_status end,
      last_seen     = now()
   where room_id = p_room and player_id = v_uid;
  perform finish_if_done(p_room);
  return jsonb_build_object('ok', true);
end $$;

-- A round is over when nobody in it is still playing. The higher score gets a win (no win on a tie).
create or replace function public.finish_if_done(p_room uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  r rooms;
  v_top int;
  v_n int;
begin
  select * into r from rooms where id = p_room;
  if r.status <> 'playing' then return; end if;
  if exists (select 1 from room_players where room_id = p_room and player_status = 'playing') then return; end if;
  select max(current_score) into v_top from room_players where room_id = p_room and round = r.round;
  select count(*) into v_n from room_players where room_id = p_room and round = r.round and current_score = v_top;
  if v_n = 1 then
    update room_players set wins = wins + 1 where room_id = p_room and round = r.round and current_score = v_top;
  end if;
  update rooms set status = 'finished', updated_at = now() where id = p_room;
end $$;

-- Heartbeat every few seconds while in a room. Also notices an opponent who went quiet.
create or replace function public.heartbeat(p_room uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform cleanup_rooms();
  if not exists (select 1 from rooms where id = p_room and status <> 'closed') then return jsonb_build_object('error', 'closed'); end if;
  -- a player who timed out and comes back is back in the room (their timed-out run stays ended)
  update room_players set last_seen = now(),
         player_status = case when player_status = 'left' then 'lobby' else player_status end
   where room_id = p_room and player_id = auth.uid();
  if not found then return jsonb_build_object('error', 'not_found'); end if;
  return jsonb_build_object('now', now());
end $$;

-- Deliberately leaving (Leave button, Menu). The other player sees "<name> left the session".
create or replace function public.leave_room(p_room uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r rooms;
begin
  update room_players set player_status = 'left', last_seen = now() where room_id = p_room and player_id = auth.uid();
  select * into r from rooms where id = p_room;
  if r.status = 'waiting' and r.host_id = auth.uid() then
    update rooms set status = 'closed', updated_at = now() where id = p_room;
  elsif r.status = 'ready' then
    -- back to waiting so the seat can be taken again
    update rooms set status = case when r.host_id = auth.uid() then 'closed' else 'waiting' end,
           guest_id = case when r.host_id = auth.uid() then guest_id else null end, updated_at = now() where id = p_room;
    if r.host_id <> auth.uid() then delete from room_players where room_id = p_room and player_id = auth.uid(); end if;
  else
    perform finish_if_done(p_room);
  end if;
  perform cleanup_rooms();
end $$;

-- Only signed-in (anonymous) players may call these; nobody may call them without signing in.
revoke all on function public.cleanup_rooms(), public.finish_if_done(uuid) from public, anon, authenticated;
revoke all on function public.create_room(text), public.find_room(text), public.join_room(text, text), public.my_room(),
  public.set_ready(uuid), public.report_run(uuid, int, int, int, boolean), public.heartbeat(uuid), public.leave_room(uuid),
  public.room_state(uuid) from public, anon;
grant execute on function public.create_room(text), public.find_room(text), public.join_room(text, text), public.my_room(),
  public.set_ready(uuid), public.report_run(uuid, int, int, int, boolean), public.heartbeat(uuid), public.leave_room(uuid),
  public.room_state(uuid) to authenticated;
revoke all on public.rooms, public.room_players from anon;
grant select on public.rooms, public.room_players to authenticated;
