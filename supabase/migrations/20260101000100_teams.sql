-- S14: persistent teams (WoW style) for 2v2 and 3v3. No rating anywhere: that is a later stage.
--
-- Rules, all enforced here:
--   * one team per mode per player; modes 2 and 3 only; up to mode * 2 members (pending invites count towards it);
--   * only the captain invites, cancels invites, kicks, hands over the captaincy or disbands;
--   * a captain cannot leave: hand over or disband; names are sanitized, 3..20 chars, unique per mode ignoring case;
--   * an invitation lives on the server (the invitee sees it when they next connect) for 7 days.
-- Clients touch nothing directly: reads are my_teams()/my_invites(), writes are the functions below.

create table public.teams (
  id uuid primary key default gen_random_uuid(),
  mode smallint not null check (mode in (2, 3)),
  name text not null check (char_length(name) between 3 and 20),
  name_key text not null,
  captain bigint not null,
  created_at timestamptz not null default now(),
  unique (id, mode),
  constraint teams_name_per_mode unique (mode, name_key)
);

create table public.team_members (
  team_id uuid not null,
  mode smallint not null,
  steam_id bigint not null,
  joined_at timestamptz not null default now(),
  primary key (team_id, steam_id),
  constraint team_members_one_per_mode unique (steam_id, mode),
  foreign key (team_id, mode) references public.teams (id, mode) on delete cascade
);

create table public.team_invites (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  mode smallint not null,
  from_steam bigint not null,
  to_steam bigint not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days',
  unique (team_id, to_steam),
  foreign key (team_id, mode) references public.teams (id, mode) on delete cascade
);
create index team_invites_to_steam_idx on public.team_invites (to_steam);

alter table public.teams enable row level security;
alter table public.teams force row level security;
alter table public.team_members enable row level security;
alter table public.team_members force row level security;
alter table public.team_invites enable row level security;
alter table public.team_invites force row level security;
revoke all on table public.teams, public.team_members, public.team_invites from public, anon, authenticated;

-- ---------------------------------------------------------------- helpers (not callable by clients)

-- The team row, locked for the rest of the transaction (serializes concurrent captains/accepts).
create function app_private.lock_team(p_team uuid) returns public.teams
language plpgsql
set search_path = ''
as $$
declare
  t public.teams;
begin
  select * into t from public.teams where id = p_team for update;
  if not found then
    raise exception 'team_not_found';
  end if;
  return t;
end;
$$;
revoke all on function app_private.lock_team(uuid) from public, anon, authenticated;

create function app_private.drop_expired_invites_for(p_team uuid, p_to bigint) returns void
language sql
set search_path = ''
as $$
  delete from public.team_invites
   where expires_at <= now() and (team_id = p_team or to_steam = p_to);
$$;
revoke all on function app_private.drop_expired_invites_for(uuid, bigint) from public, anon, authenticated;

-- ---------------------------------------------------------------- reads (Steam ids as text: see the base migration)

create function public.my_teams() returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  me bigint := app_private.me();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', t.id,
      'mode', t.mode,
      'name', t.name,
      'captain', t.captain::text,
      'members', (
        select coalesce(jsonb_agg(jsonb_build_object(
                 'steam_id', m.steam_id::text,
                 'name', coalesce(p.name, m.steam_id::text),
                 'captain', m.steam_id = t.captain
               ) order by (m.steam_id = t.captain) desc, m.joined_at, m.steam_id), '[]'::jsonb)
          from public.team_members m left join public.players p on p.steam_id = m.steam_id
         where m.team_id = t.id),
      'invites', (
        select coalesce(jsonb_agg(jsonb_build_object(
                 'id', i.id,
                 'to', i.to_steam::text,
                 'to_name', coalesce(p.name, i.to_steam::text),
                 'expires_at', i.expires_at
               ) order by i.created_at), '[]'::jsonb)
          from public.team_invites i left join public.players p on p.steam_id = i.to_steam
         where i.team_id = t.id and i.expires_at > now())
    ) order by t.mode, t.created_at)
    from public.teams t
    join public.team_members me_m on me_m.team_id = t.id and me_m.steam_id = me
  ), '[]'::jsonb);
end;
$$;

create function public.my_invites() returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  me bigint := app_private.me();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', i.id,
      'team_id', i.team_id,
      'team_name', t.name,
      'mode', i.mode,
      'from', i.from_steam::text,
      'from_name', coalesce(p.name, i.from_steam::text),
      'expires_at', i.expires_at
    ) order by i.created_at)
    from public.team_invites i
    join public.teams t on t.id = i.team_id
    left join public.players p on p.steam_id = i.from_steam
    where i.to_steam = me and i.expires_at > now()
  ), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------- writes

create function public.create_team(p_mode int, p_name text) returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  me bigint := app_private.me();
  v_name text;
  v_id uuid;
begin
  if p_mode is null or p_mode not in (2, 3) then
    raise exception 'invalid_mode';
  end if;
  v_name := app_private.clean_name(p_name, 3, 20);
  if exists (select 1 from public.team_members where steam_id = me and mode = p_mode) then
    raise exception 'already_in_team';
  end if;
  begin
    insert into public.teams (mode, name, name_key, captain)
    values (p_mode, v_name, pg_catalog.lower(v_name), me)
    returning id into v_id;
    insert into public.team_members (team_id, mode, steam_id) values (v_id, p_mode, me);
  exception when unique_violation then
    declare c text;
    begin
      get stacked diagnostics c = constraint_name;
      if c = 'teams_name_per_mode' then
        raise exception 'name_taken';
      end if;
      raise exception 'already_in_team';
    end;
  end;
  return v_id;
end;
$$;

create function public.invite_to_team(p_team uuid, p_steam_id bigint) returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  me bigint := app_private.me();
  t public.teams := app_private.lock_team(p_team);
  v_id uuid;
begin
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

create function public.accept_invite(p_invite uuid) returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  me bigint := app_private.me();
  v_team uuid;
  t public.teams;
begin
  select team_id into v_team from public.team_invites
   where id = p_invite and to_steam = me and expires_at > now();
  if not found then
    raise exception 'invite_not_found';
  end if;
  t := app_private.lock_team(v_team);
  perform 1 from public.team_invites
   where id = p_invite and to_steam = me and expires_at > now() for update;
  if not found then
    raise exception 'invite_not_found';
  end if;
  if exists (select 1 from public.team_members where steam_id = me and mode = t.mode) then
    raise exception 'already_in_team';
  end if;
  if (select count(*) from public.team_members where team_id = v_team) >= t.mode * 2 then
    raise exception 'team_full';
  end if;
  insert into public.team_members (team_id, mode, steam_id) values (v_team, t.mode, me);
  -- Joined: this invitation and the player's other pending ones for the same mode are spent.
  delete from public.team_invites where to_steam = me and mode = t.mode;
  return v_team;
end;
$$;

create function public.decline_invite(p_invite uuid) returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  me bigint := app_private.me();
begin
  delete from public.team_invites where id = p_invite and to_steam = me;
  if not found then
    raise exception 'invite_not_found';
  end if;
end;
$$;

create function public.cancel_invite(p_invite uuid) returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  me bigint := app_private.me();
  v_team uuid;
  t public.teams;
begin
  select team_id into v_team from public.team_invites where id = p_invite;
  if not found then
    raise exception 'invite_not_found';
  end if;
  t := app_private.lock_team(v_team);
  if t.captain <> me then
    raise exception 'not_captain';
  end if;
  delete from public.team_invites where id = p_invite;
end;
$$;

create function public.leave_team(p_team uuid) returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  me bigint := app_private.me();
  t public.teams := app_private.lock_team(p_team);
begin
  if not exists (select 1 from public.team_members where team_id = p_team and steam_id = me) then
    raise exception 'not_member';
  end if;
  if t.captain = me then
    raise exception 'captain_must_transfer_or_disband';
  end if;
  delete from public.team_members where team_id = p_team and steam_id = me;
end;
$$;

create function public.kick_member(p_team uuid, p_steam_id bigint) returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  me bigint := app_private.me();
  t public.teams := app_private.lock_team(p_team);
begin
  if t.captain <> me then
    raise exception 'not_captain';
  end if;
  if p_steam_id is null or p_steam_id = me then
    raise exception 'invalid_target';
  end if;
  delete from public.team_members where team_id = p_team and steam_id = p_steam_id;
  if not found then
    raise exception 'not_member';
  end if;
end;
$$;

create function public.transfer_captain(p_team uuid, p_steam_id bigint) returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  me bigint := app_private.me();
  t public.teams := app_private.lock_team(p_team);
begin
  if t.captain <> me then
    raise exception 'not_captain';
  end if;
  if p_steam_id is null or p_steam_id = me then
    raise exception 'invalid_target';
  end if;
  if not exists (select 1 from public.team_members where team_id = p_team and steam_id = p_steam_id) then
    raise exception 'not_member';
  end if;
  update public.teams set captain = p_steam_id where id = p_team;
end;
$$;

create function public.disband_team(p_team uuid) returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  me bigint := app_private.me();
  t public.teams := app_private.lock_team(p_team);
begin
  if t.captain <> me then
    raise exception 'not_captain';
  end if;
  delete from public.teams where id = p_team;  -- members and invitations go with it (cascade)
end;
$$;

revoke all on function
  public.my_teams(), public.my_invites(), public.create_team(int, text), public.invite_to_team(uuid, bigint),
  public.accept_invite(uuid), public.decline_invite(uuid), public.cancel_invite(uuid), public.leave_team(uuid),
  public.kick_member(uuid, bigint), public.transfer_captain(uuid, bigint), public.disband_team(uuid)
  from public, anon;
grant execute on function
  public.my_teams(), public.my_invites(), public.create_team(int, text), public.invite_to_team(uuid, bigint),
  public.accept_invite(uuid), public.decline_invite(uuid), public.cancel_invite(uuid), public.leave_team(uuid),
  public.kick_member(uuid, bigint), public.transfer_captain(uuid, bigint), public.disband_team(uuid)
  to authenticated;
