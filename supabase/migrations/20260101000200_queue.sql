-- S16 + S18: play groups (per-member confirmation), the normal queue with hidden skill, and result reporting.
--
-- Rules, all enforced here (the client only asks and polls):
--   * Normal queue only: 1v1, 2v2 and 3v3. Teams, groups and solos fill two sides of `mode` players each, never with bots.
--     A ticket (solo, group or team) always lands on ONE side, so teammates and group members play together.
--   * Pairing is by mode and exact game version. Each player has a hidden skill per mode (default 1500, Ranked.START)
--     in `player_skill`: no table grant and no RPC ever returns it. A ticket's skill is the average of its members.
--     The accepted skill gap widens with the wait like Ranked.window (200 + 10 per second, at most 800).
--   * Pairing locks tickets (`for update` on the caller's ticket, `skip locked` on candidates) so two concurrent polls can
--     never use the same ticket twice; a partial unique index on active match players is the backstop.
--   * A ticket expires 20 s after any of its members stops polling `queue_status`.
--   * Results: every player may report the winning side once. The match resolves only when BOTH sides reported and all
--     reports agree; then the hidden skill changes (same formula as Ranked.delta). If reports disagree, or one side
--     never reports within 30 minutes, nothing changes. No disputes and no penalty for leaving.
--   * Simple per-player rate limits on the RPCs that write (see app_private.rate_check). Failed calls roll back and do
--     not count: the limit bounds successful writes (invites, queue churn), not probing.

-- ---------------------------------------------------------------- tables (clients get no privileges at all)

create table public.rate_limits (
  steam_id bigint not null,
  bucket text not null,
  window_start timestamptz not null,
  n int not null,
  primary key (steam_id, bucket)
);

-- Hidden. Read by no RPC.
create table public.player_skill (
  steam_id bigint not null,
  mode smallint not null check (mode in (1, 2, 3)),
  skill int not null default 1500 check (skill between 0 and 5000),
  games int not null default 0,
  updated_at timestamptz not null default now(),
  primary key (steam_id, mode)
);

create table public.play_groups (
  id uuid primary key default gen_random_uuid(),
  mode smallint not null check (mode in (2, 3)),
  team_id uuid references public.teams (id) on delete cascade,
  leader bigint not null,
  created_at timestamptz not null default now()
);
create table public.play_group_members (
  group_id uuid not null references public.play_groups (id) on delete cascade,
  steam_id bigint not null,
  confirmed boolean not null default false,
  invited_at timestamptz not null default now(),
  primary key (group_id, steam_id)
);
-- A player is confirmed in at most one group; any number of pending invitations (capped by the RPC).
create unique index play_group_members_one_confirmed on public.play_group_members (steam_id) where confirmed;
create index play_group_members_steam_idx on public.play_group_members (steam_id);

create table public.online_matches (
  id uuid primary key default gen_random_uuid(),
  mode smallint not null check (mode in (1, 2, 3)),
  version text not null,
  status text not null default 'open' check (status in ('open', 'resolved', 'void')),
  host bigint not null,
  lobby_id text,
  winner text check (winner in ('red', 'blue')),
  created_at timestamptz not null default clock_timestamp(),
  resolved_at timestamptz
);
create table public.online_match_players (
  match_id uuid not null references public.online_matches (id) on delete cascade,
  steam_id bigint not null,
  side text not null check (side in ('red', 'blue')),
  team_id uuid,
  skill float8 not null,          -- snapshot taken when the match was formed (hidden)
  active boolean not null default true,
  reported text check (reported in ('red', 'blue')),
  created_at timestamptz not null default clock_timestamp(),
  primary key (match_id, steam_id)
);
-- A player is in at most one live match, whatever concurrent polls do.
create unique index online_match_players_one_active on public.online_match_players (steam_id) where active;

create table public.queue_tickets (
  id uuid primary key default gen_random_uuid(),
  mode smallint not null check (mode in (1, 2, 3)),
  version text not null,
  group_id uuid references public.play_groups (id) on delete cascade,
  team_id uuid,
  leader bigint not null,
  size int not null check (size between 1 and 3),
  skill float8 not null,          -- average of the members (hidden)
  status text not null default 'searching' check (status in ('searching', 'matched')),
  match_id uuid references public.online_matches (id) on delete set null,
  created_at timestamptz not null default now()
);
create index queue_tickets_search_idx on public.queue_tickets (mode, version) where status = 'searching';
create table public.ticket_members (
  steam_id bigint primary key,    -- one queue ticket per player
  ticket_id uuid not null references public.queue_tickets (id) on delete cascade,
  skill float8 not null,
  last_poll timestamptz not null
);
create index ticket_members_ticket_idx on public.ticket_members (ticket_id);

alter table public.rate_limits enable row level security;
alter table public.rate_limits force row level security;
alter table public.player_skill enable row level security;
alter table public.player_skill force row level security;
alter table public.play_groups enable row level security;
alter table public.play_groups force row level security;
alter table public.play_group_members enable row level security;
alter table public.play_group_members force row level security;
alter table public.online_matches enable row level security;
alter table public.online_matches force row level security;
alter table public.online_match_players enable row level security;
alter table public.online_match_players force row level security;
alter table public.queue_tickets enable row level security;
alter table public.queue_tickets force row level security;
alter table public.ticket_members enable row level security;
alter table public.ticket_members force row level security;
revoke all on table public.rate_limits, public.player_skill, public.play_groups, public.play_group_members,
  public.online_matches, public.online_match_players, public.queue_tickets, public.ticket_members
  from public, anon, authenticated;

-- ---------------------------------------------------------------- helpers (not callable by clients)

-- Ranked.delta in SQL: Elo change for one player, `my` team average against `their`, `games` already played.
create function app_private.skill_delta(p_my float8, p_their float8, p_won boolean, p_games int) returns int
language plpgsql immutable
set search_path = ''
as $$
declare
  k float8 := case when p_games < 5 then 48.0 else 24.0 end;
  e float8 := 1.0 / (1.0 + power(10.0::float8, (p_their - p_my) / 400.0));
  x float8 := k * ((case when p_won then 1.0 else 0.0 end) - e);
  d int := (sign(x) * floor(abs(x) + 0.5))::int;   -- rounds half away from zero, like GDScript roundi
begin
  if d = 0 then
    d := case when p_won then 1 else -1 end;       -- a match always counts for something
  end if;
  return d;
end;
$$;

create function app_private.clamp_skill(p_v int) returns int
language sql immutable
set search_path = ''
as $$ select greatest(0, least(5000, p_v)) $$;

-- Ranked.window: accepted skill gap after waiting this many seconds.
create function app_private.skill_window(p_waited float8) returns int
language sql immutable
set search_path = ''
as $$ select least(200 + floor(greatest(p_waited, 0) * 10.0)::int, 800) $$;

-- Per-player rate limit for the calling player: raises rate_limited when this is call number p_max + 1 inside the window.
-- The raise rolls the counter back too, so only calls that went through are counted.
create function app_private.rate_check(p_bucket text, p_max int, p_window_s int) returns void
language plpgsql
set search_path = ''
as $$
declare
  me bigint := app_private.me();
  v_n int;
begin
  insert into public.rate_limits as r (steam_id, bucket, window_start, n)
  values (me, p_bucket, now(), 1)
  on conflict (steam_id, bucket) do update set
    n = case when r.window_start <= now() - make_interval(secs => p_window_s) then 1 else r.n + 1 end,
    window_start = case when r.window_start <= now() - make_interval(secs => p_window_s) then now() else r.window_start end
  returning n into v_n;
  if v_n > p_max then
    raise exception 'rate_limited';
  end if;
end;
$$;

-- Drops what has gone stale: tickets whose members stopped polling, old matched tickets, matches nobody settled in time,
-- old groups. Skips rows another transaction holds, so it never blocks pairing.
create function app_private.sweep() returns void
language plpgsql
set search_path = ''
as $$
begin
  delete from public.queue_tickets
   where id in (select t.id from public.queue_tickets t
                 where t.status = 'searching'
                   and exists (select 1 from public.ticket_members m
                                where m.ticket_id = t.id and m.last_poll < now() - interval '20 seconds')
                 for update skip locked);
  update public.online_matches set status = 'void', resolved_at = now()
   where id in (select id from public.online_matches
                 where status = 'open' and created_at < now() - interval '30 minutes' for update skip locked);
  update public.online_match_players set active = false
   where active and match_id in (select id from public.online_matches where status <> 'open');
  delete from public.queue_tickets
   where status = 'matched' and (created_at < now() - interval '2 hours'
      or match_id in (select id from public.online_matches where status <> 'open'));
  delete from public.play_groups
   where created_at < now() - interval '6 hours'
     and not exists (select 1 from public.queue_tickets t where t.group_id = play_groups.id);
end;
$$;

-- Depth-first search for two sides of p_m players out of the caller's ticket (side 1, size p_a already) and the
-- candidates in order (p_sizes). Returns the side of each candidate (0 = not used) or null when it cannot be filled.
create function app_private.fill_sides(p_sizes int[], p_i int, p_a int, p_b int, p_m int, p_cur int[]) returns int[]
language plpgsql immutable
set search_path = ''
as $$
declare
  r int[];
begin
  if p_a = p_m and p_b = p_m then
    return p_cur;
  end if;
  if p_i > coalesce(array_length(p_sizes, 1), 0) then
    return null;
  end if;
  if p_b + p_sizes[p_i] <= p_m then
    r := app_private.fill_sides(p_sizes, p_i + 1, p_a, p_b + p_sizes[p_i], p_m, p_cur || 2);
    if r is not null then return r; end if;
  end if;
  if p_a + p_sizes[p_i] <= p_m then
    r := app_private.fill_sides(p_sizes, p_i + 1, p_a + p_sizes[p_i], p_b, p_m, p_cur || 1);
    if r is not null then return r; end if;
  end if;
  return app_private.fill_sides(p_sizes, p_i + 1, p_a, p_b, p_m, p_cur || 0);
end;
$$;

-- Tries to complete a match around one searching ticket. Concurrency: the ticket is locked first (a poll that lost the
-- race waits, then sees it is matched and leaves), candidates are taken with skip locked (a locked one belongs to another
-- pairing in progress and is simply not available this time; the next poll retries).
create function app_private.try_match(p_ticket uuid) returns void
language plpgsql
set search_path = ''
as $$
declare
  t public.queue_tickets;
  v_waited float8;
  v_ids uuid[];
  v_sizes int[];
  v_assign int[];
  v_match uuid;
  v_host bigint;
  v_flip boolean := pg_catalog.random() < 0.5;
  v_chosen uuid[] := '{}';
  i int;
begin
  select * into t from public.queue_tickets where id = p_ticket and status = 'searching' for update;
  if not found then
    return;
  end if;
  v_waited := extract(epoch from now() - t.created_at);
  select coalesce(array_agg(q.id order by q.ord), '{}'), coalesce(array_agg(q.size order by q.ord), '{}')
    into v_ids, v_sizes
    from (select c2.id, c2.size, row_number() over (order by abs(c2.skill - t.skill), c2.created_at, c2.id) as ord
            from (select * from public.queue_tickets c
                   where c.status = 'searching' and c.id <> t.id and c.mode = t.mode and c.version = t.version
                     and abs(c.skill - t.skill) <= app_private.skill_window(greatest(v_waited, extract(epoch from now() - c.created_at)))
                     and not exists (select 1 from public.ticket_members m
                                      where m.ticket_id = c.id and m.last_poll < now() - interval '20 seconds')
                   order by abs(c.skill - t.skill), c.created_at, c.id
                   limit 8
                   for update of c skip locked) c2) q;
  if coalesce(array_length(v_ids, 1), 0) = 0 then
    return;
  end if;
  v_assign := app_private.fill_sides(v_sizes, 1, t.size, 0, t.mode, '{}');
  if v_assign is null then
    return;
  end if;
  for i in 1..coalesce(array_length(v_assign, 1), 0) loop
    if v_assign[i] <> 0 then
      v_chosen := v_chosen || v_ids[i];
    end if;
  end loop;
  -- the longest waiting ticket's leader hosts
  select leader into v_host from public.queue_tickets where id = any (v_chosen || t.id) order by created_at, id limit 1;
  insert into public.online_matches (mode, version, host) values (t.mode, t.version, v_host) returning id into v_match;
  insert into public.online_match_players (match_id, steam_id, side, team_id, skill)
  select v_match, m.steam_id,
         case when (x.side = 1) = v_flip then 'red' else 'blue' end,
         x.team_id, m.skill
    from (select t.id as ticket_id, 1 as side, t.team_id
          union all
          select v_ids[g], v_assign[g], (select qt.team_id from public.queue_tickets qt where qt.id = v_ids[g])
            from generate_subscripts(v_assign, 1) g where v_assign[g] <> 0) x
    join public.ticket_members m on m.ticket_id = x.ticket_id;
  update public.queue_tickets set status = 'matched', match_id = v_match where id = any (v_chosen || t.id);
end;
$$;

-- Settles a match after a report. Both sides reported and every report agrees: resolved, hidden skill moves.
-- Any disagreement: void, nothing moves. Otherwise it stays open (the timeout in sweep() closes it).
create function app_private.settle(p_match uuid) returns void
language plpgsql
set search_path = ''
as $$
declare
  m public.online_matches;
  v_winners int;
  v_reds int;
  v_blues int;
  v_winner text;
  p record;
  v_my float8;
  v_their float8;
  v_games int;
  v_skill int;
begin
  select * into m from public.online_matches where id = p_match for update;
  if not found or m.status <> 'open' then
    return;
  end if;
  select count(distinct reported), count(*) filter (where side = 'red' and reported is not null),
         count(*) filter (where side = 'blue' and reported is not null), min(reported)
    into v_winners, v_reds, v_blues, v_winner
    from public.online_match_players where match_id = p_match;
  if v_winners > 1 then
    update public.online_matches set status = 'void', resolved_at = now() where id = p_match;
  elsif v_reds > 0 and v_blues > 0 then
    for p in select * from public.online_match_players where match_id = p_match loop
      select avg(skill) into v_my from public.online_match_players where match_id = p_match and side = p.side;
      select avg(skill) into v_their from public.online_match_players where match_id = p_match and side <> p.side;
      select coalesce(max(games), 0), coalesce(max(skill), 1500) into v_games, v_skill
        from public.player_skill where steam_id = p.steam_id and mode = m.mode;
      insert into public.player_skill (steam_id, mode, skill, games)
      values (p.steam_id, m.mode,
              app_private.clamp_skill(v_skill + app_private.skill_delta(v_my, coalesce(v_their, v_my), p.side = v_winner, v_games)),
              v_games + 1)
      on conflict (steam_id, mode) do update set skill = excluded.skill, games = excluded.games, updated_at = now();
    end loop;
    update public.online_matches set status = 'resolved', winner = v_winner, resolved_at = now() where id = p_match;
  else
    return;
  end if;
  update public.online_match_players set active = false where match_id = p_match;
  delete from public.queue_tickets where match_id = p_match;
end;
$$;

revoke all on function
  app_private.skill_delta(float8, float8, boolean, int), app_private.clamp_skill(int), app_private.skill_window(float8),
  app_private.rate_check(text, int, int), app_private.sweep(), app_private.fill_sides(int[], int, int, int, int, int[]),
  app_private.try_match(uuid), app_private.settle(uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------- groups

create function public.create_group(p_mode int, p_team uuid default null) returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  me bigint := app_private.me();
  v_id uuid;
  t public.teams;
begin
  perform app_private.rate_check('group', 20, 60);
  if p_mode is null or p_mode not in (2, 3) then
    raise exception 'invalid_mode';
  end if;
  if exists (select 1 from public.play_group_members where steam_id = me and confirmed) then
    raise exception 'already_in_group';
  end if;
  if exists (select 1 from public.ticket_members where steam_id = me) then
    raise exception 'already_queued';
  end if;
  if p_team is not null then
    t := app_private.lock_team(p_team);
    if t.mode <> p_mode then
      raise exception 'invalid_mode';
    end if;
    if t.captain <> me then
      raise exception 'not_captain';
    end if;
  end if;
  insert into public.play_groups (mode, team_id, leader) values (p_mode, p_team, me) returning id into v_id;
  insert into public.play_group_members (group_id, steam_id, confirmed) values (v_id, me, true);
  return v_id;
end;
$$;

create function public.group_add(p_group uuid, p_steam_id bigint) returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  me bigint := app_private.me();
  g public.play_groups;
begin
  perform app_private.rate_check('group', 20, 60);
  select * into g from public.play_groups where id = p_group for update;
  if not found then
    raise exception 'group_not_found';
  end if;
  if g.leader <> me then
    raise exception 'not_leader';
  end if;
  if exists (select 1 from public.queue_tickets where group_id = p_group) then
    raise exception 'group_locked';
  end if;
  if p_steam_id is null or p_steam_id <= 0 or p_steam_id > 999999999999999999 or p_steam_id = me then
    raise exception 'invalid_target';
  end if;
  if g.team_id is not null
     and not exists (select 1 from public.team_members where team_id = g.team_id and steam_id = p_steam_id) then
    raise exception 'not_member';
  end if;
  if exists (select 1 from public.play_group_members where group_id = p_group and steam_id = p_steam_id) then
    raise exception 'already_invited';
  end if;
  if (select count(*) from public.play_group_members where group_id = p_group) >= g.mode then
    raise exception 'group_full';
  end if;
  if (select count(*) from public.play_group_members where steam_id = p_steam_id and not confirmed) >= 10 then
    raise exception 'invitee_inbox_full';
  end if;
  insert into public.play_group_members (group_id, steam_id) values (p_group, p_steam_id);
end;
$$;

create function public.group_confirm(p_group uuid) returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  me bigint := app_private.me();
  g public.play_groups;
begin
  select * into g from public.play_groups where id = p_group for update;
  if not found or not exists (select 1 from public.play_group_members where group_id = p_group and steam_id = me and not confirmed) then
    raise exception 'group_not_found';
  end if;
  if exists (select 1 from public.play_group_members where steam_id = me and confirmed) then
    raise exception 'already_in_group';
  end if;
  if exists (select 1 from public.ticket_members where steam_id = me) then
    raise exception 'already_queued';
  end if;
  update public.play_group_members set confirmed = true where group_id = p_group and steam_id = me;
  -- joined one: the other pending invitations are spent
  delete from public.play_group_members where steam_id = me and not confirmed;
end;
$$;

create function public.group_decline(p_group uuid) returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  me bigint := app_private.me();
begin
  delete from public.play_group_members where group_id = p_group and steam_id = me and not confirmed;
  if not found then
    raise exception 'group_not_found';
  end if;
end;
$$;

create function public.leave_group(p_group uuid) returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  me bigint := app_private.me();
  g public.play_groups;
begin
  select * into g from public.play_groups where id = p_group for update;
  if not found or not exists (select 1 from public.play_group_members where group_id = p_group and steam_id = me and confirmed) then
    raise exception 'group_not_found';
  end if;
  if g.leader = me then
    delete from public.play_groups where id = p_group;   -- members and any ticket go with it
    return;
  end if;
  if exists (select 1 from public.queue_tickets where group_id = p_group) then
    raise exception 'group_locked';
  end if;
  delete from public.play_group_members where group_id = p_group and steam_id = me;
end;
$$;

create function public.group_kick(p_group uuid, p_steam_id bigint) returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  me bigint := app_private.me();
  g public.play_groups;
begin
  select * into g from public.play_groups where id = p_group for update;
  if not found then
    raise exception 'group_not_found';
  end if;
  if g.leader <> me then
    raise exception 'not_leader';
  end if;
  if p_steam_id is null or p_steam_id = me then
    raise exception 'invalid_target';
  end if;
  if exists (select 1 from public.queue_tickets where group_id = p_group) then
    raise exception 'group_locked';
  end if;
  delete from public.play_group_members where group_id = p_group and steam_id = p_steam_id;
  if not found then
    raise exception 'not_member';
  end if;
end;
$$;

-- The caller's confirmed group (null when none). Steam ids as text.
create function public.my_group() returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  me bigint := app_private.me();
begin
  return (
    select jsonb_build_object(
      'id', g.id,
      'mode', g.mode,
      'team_id', g.team_id,
      'leader', g.leader::text,
      'queued', exists (select 1 from public.queue_tickets t where t.group_id = g.id),
      'members', (select coalesce(jsonb_agg(jsonb_build_object(
                    'steam_id', m.steam_id::text,
                    'name', coalesce(p.name, m.steam_id::text),
                    'confirmed', m.confirmed) order by (m.steam_id = g.leader) desc, m.invited_at, m.steam_id), '[]'::jsonb)
                    from public.play_group_members m left join public.players p on p.steam_id = m.steam_id
                   where m.group_id = g.id))
      from public.play_groups g
      join public.play_group_members mine on mine.group_id = g.id and mine.steam_id = me and mine.confirmed
  );
end;
$$;

create function public.my_group_invites() returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  me bigint := app_private.me();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', g.id,
      'mode', g.mode,
      'from', g.leader::text,
      'from_name', coalesce(p.name, g.leader::text),
      'team_name', tm.name
    ) order by m.invited_at)
    from public.play_group_members m
    join public.play_groups g on g.id = m.group_id
    left join public.players p on p.steam_id = g.leader
    left join public.teams tm on tm.id = g.team_id
    where m.steam_id = me and not m.confirmed
  ), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------- queue

create function public.join_queue(p_mode int, p_version text, p_group uuid default null) returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  me bigint := app_private.me();
  v_version text := pg_catalog.btrim(coalesce(p_version, ''));
  g public.play_groups;
  v_ticket uuid;
  v_members bigint[];
  v_skill float8;
  v_size int;
  v_m bigint;
  s float8;
  v_sum float8 := 0;
begin
  perform app_private.rate_check('join_queue', 10, 60);
  if p_mode is null or p_mode not in (1, 2, 3) then
    raise exception 'invalid_mode';
  end if;
  if v_version !~ '^[A-Za-z0-9._+-]{1,40}$' then
    raise exception 'invalid_version';
  end if;
  perform app_private.sweep();
  if p_group is null then
    v_members := array[me];
  else
    select * into g from public.play_groups where id = p_group for update;
    if not found or not exists (select 1 from public.play_group_members where group_id = p_group and steam_id = me and confirmed) then
      raise exception 'group_not_found';
    end if;
    if g.leader <> me then
      raise exception 'not_leader';
    end if;
    if g.mode <> p_mode then
      raise exception 'invalid_mode';
    end if;
    if exists (select 1 from public.play_group_members where group_id = p_group and not confirmed) then
      raise exception 'not_confirmed';
    end if;
    select array_agg(steam_id order by steam_id) into v_members from public.play_group_members where group_id = p_group;
  end if;
  if exists (select 1 from public.online_match_players where steam_id = any (v_members) and active) then
    raise exception 'already_in_match';
  end if;
  if exists (select 1 from public.ticket_members where steam_id = any (v_members)) then
    raise exception 'already_queued';
  end if;
  v_size := array_length(v_members, 1);
  foreach v_m in array v_members loop
    select coalesce(max(skill), 1500) into s from public.player_skill where steam_id = v_m and mode = p_mode;
    v_sum := v_sum + s;
  end loop;
  v_skill := v_sum / v_size;
  insert into public.queue_tickets (mode, version, group_id, team_id, leader, size, skill)
  values (p_mode, v_version, p_group, g.team_id, me, v_size, v_skill) returning id into v_ticket;
  foreach v_m in array v_members loop
    select coalesce(max(skill), 1500) into s from public.player_skill where steam_id = v_m and mode = p_mode;
    -- the others get a little grace to start polling
    insert into public.ticket_members (steam_id, ticket_id, skill, last_poll)
    values (v_m, v_ticket, s, case when v_m = me then now() else now() + interval '25 seconds' end);
  end loop;
  perform app_private.try_match(v_ticket);
end;
$$;

-- Leaves the queue (the whole ticket when searching: the group has to search again) or, when already matched, lets go
-- of the match (no report, no penalty) so a new search is possible.
create function public.leave_queue() returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  me bigint := app_private.me();
  t public.queue_tickets;
begin
  select qt.* into t from public.queue_tickets qt
    join public.ticket_members m on m.ticket_id = qt.id where m.steam_id = me;
  if found then
    if t.status = 'searching' then
      delete from public.queue_tickets where id = t.id;
    else
      delete from public.ticket_members where steam_id = me;
      delete from public.queue_tickets where id = t.id and not exists (select 1 from public.ticket_members where ticket_id = t.id);
    end if;
  end if;
  update public.online_match_players set active = false where steam_id = me and active;
end;
$$;

-- The one thing clients poll: only status, how many are searching, the wait, the lobby id and the sides.
create function public.queue_status() returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  me bigint := app_private.me();
  t public.queue_tickets;
  m public.online_matches;
  v_side text;
  v_searching int;
begin
  perform app_private.rate_check('queue_status', 60, 60);
  update public.ticket_members set last_poll = now() where steam_id = me;
  perform app_private.sweep();
  select qt.* into t from public.queue_tickets qt join public.ticket_members tm on tm.ticket_id = qt.id where tm.steam_id = me;
  if not found then
    return jsonb_build_object('state', 'idle');
  end if;
  if t.status = 'searching' then
    perform app_private.try_match(t.id);
    select * into t from public.queue_tickets where id = t.id;
  end if;
  if t.status = 'searching' then
    select coalesce(sum(size), 0) into v_searching from public.queue_tickets
     where status = 'searching' and mode = t.mode and version = t.version;
    return jsonb_build_object('state', 'searching', 'mode', t.mode, 'searching', v_searching,
                              'wait', floor(extract(epoch from now() - t.created_at))::int);
  end if;
  select * into m from public.online_matches where id = t.match_id;
  select side into v_side from public.online_match_players where match_id = m.id and steam_id = me;
  return jsonb_build_object(
    'state', 'matched', 'mode', m.mode,
    'wait', floor(extract(epoch from now() - t.created_at))::int,
    'match', jsonb_build_object(
      'id', m.id,
      'host', m.host::text,
      'is_host', m.host = me,
      'lobby_id', m.lobby_id,
      'side', v_side,
      'sides', jsonb_build_object(
        'red', (select coalesce(jsonb_agg(jsonb_build_object('steam_id', p.steam_id::text, 'name', coalesce(pl.name, p.steam_id::text))
                  order by p.steam_id), '[]'::jsonb)
                  from public.online_match_players p left join public.players pl on pl.steam_id = p.steam_id
                 where p.match_id = m.id and p.side = 'red'),
        'blue', (select coalesce(jsonb_agg(jsonb_build_object('steam_id', p.steam_id::text, 'name', coalesce(pl.name, p.steam_id::text))
                  order by p.steam_id), '[]'::jsonb)
                  from public.online_match_players p left join public.players pl on pl.steam_id = p.steam_id
                 where p.match_id = m.id and p.side = 'blue'))));
end;
$$;

-- The host of a match publishes its Steam lobby id (text: it does not fit in a JSON double).
create function public.publish_lobby(p_match uuid, p_lobby text) returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  me bigint := app_private.me();
  m public.online_matches;
begin
  perform app_private.rate_check('publish', 20, 60);
  select * into m from public.online_matches where id = p_match for update;
  if not found or not exists (select 1 from public.online_match_players where match_id = p_match and steam_id = me) then
    raise exception 'not_in_match';
  end if;
  if m.host <> me then
    raise exception 'not_host';
  end if;
  if p_lobby is null or p_lobby !~ '^[0-9]{5,20}$' then
    raise exception 'invalid_lobby';
  end if;
  if m.status <> 'open' then
    raise exception 'match_closed';
  end if;
  update public.online_matches set lobby_id = p_lobby where id = p_match;
end;
$$;

create function public.report_result(p_match uuid, p_winner text) returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  me bigint := app_private.me();
  m public.online_matches;
  v_reported text;
begin
  perform app_private.rate_check('report', 20, 60);
  if p_winner is null or p_winner not in ('red', 'blue') then
    raise exception 'invalid_winner';
  end if;
  select * into m from public.online_matches where id = p_match for update;
  if not found or not exists (select 1 from public.online_match_players where match_id = p_match and steam_id = me) then
    raise exception 'not_in_match';
  end if;
  if m.status <> 'open' then
    raise exception 'match_closed';
  end if;
  select reported into v_reported from public.online_match_players where match_id = p_match and steam_id = me;
  if v_reported is not null then
    raise exception 'already_reported';
  end if;
  update public.online_match_players set reported = p_winner where match_id = p_match and steam_id = me;
  perform app_private.settle(p_match);
end;
$$;

-- Last resolved matches of a team (for the team screen). No skill, no rating: only who won.
create function public.team_history(p_team uuid) returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  me bigint := app_private.me();
begin
  if not exists (select 1 from public.team_members where team_id = p_team and steam_id = me) then
    raise exception 'not_member';
  end if;
  return coalesce((
    select jsonb_agg(h.row order by h.at desc) from (
      select m.resolved_at as at, jsonb_build_object(
        'at', m.resolved_at,
        'mode', m.mode,
        'won', m.winner = mine.side,
        'opponents', (select coalesce(jsonb_agg(coalesce(pl.name, o.steam_id::text) order by o.steam_id), '[]'::jsonb)
                        from public.online_match_players o left join public.players pl on pl.steam_id = o.steam_id
                       where o.match_id = m.id and o.side <> mine.side)) as row
        from public.online_matches m
        join lateral (select p.side from public.online_match_players p where p.match_id = m.id and p.team_id = p_team limit 1) mine on true
       where m.status = 'resolved'
       order by m.resolved_at desc limit 20) h
  ), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------- rate limits on the earlier writes

create or replace function public.invite_to_team(p_team uuid, p_steam_id bigint) returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  me bigint := app_private.me();
  t public.teams := app_private.lock_team(p_team);
  v_id uuid;
begin
  perform app_private.rate_check('invite', 20, 60);
  if t.captain <> me then
    raise exception 'not_captain';
  end if;
  if p_steam_id is null or p_steam_id <= 0 or p_steam_id > 999999999999999999 or p_steam_id = me then
    raise exception 'invalid_target';
  end if;
  perform app_private.drop_expired_invites_for(p_team, p_steam_id);
  if exists (select 1 from public.team_members where steam_id = p_steam_id and mode = t.mode) then
    raise exception 'already_in_team';
  end if;
  if exists (select 1 from public.team_invites where team_id = p_team and to_steam = p_steam_id) then
    raise exception 'already_invited';
  end if;
  if (select count(*) from public.team_members where team_id = p_team)
     + (select count(*) from public.team_invites where team_id = p_team) >= t.mode * 2 then
    raise exception 'team_full';
  end if;
  if (select count(*) from public.team_invites where to_steam = p_steam_id) >= 20 then
    raise exception 'invitee_inbox_full';
  end if;
  insert into public.team_invites (team_id, mode, from_steam, to_steam)
  values (p_team, t.mode, me, p_steam_id) returning id into v_id;
  return v_id;
end;
$$;

revoke all on function
  public.create_group(int, uuid), public.group_add(uuid, bigint), public.group_confirm(uuid), public.group_decline(uuid),
  public.leave_group(uuid), public.group_kick(uuid, bigint), public.my_group(), public.my_group_invites(),
  public.join_queue(int, text, uuid), public.leave_queue(), public.queue_status(), public.publish_lobby(uuid, text),
  public.report_result(uuid, text), public.team_history(uuid), public.invite_to_team(uuid, bigint)
  from public, anon;
grant execute on function
  public.create_group(int, uuid), public.group_add(uuid, bigint), public.group_confirm(uuid), public.group_decline(uuid),
  public.leave_group(uuid), public.group_kick(uuid, bigint), public.my_group(), public.my_group_invites(),
  public.join_queue(int, text, uuid), public.leave_queue(), public.queue_status(), public.publish_lobby(uuid, text),
  public.report_result(uuid, text), public.team_history(uuid), public.invite_to_team(uuid, bigint)
  to authenticated;
