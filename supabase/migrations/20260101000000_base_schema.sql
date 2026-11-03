-- S12: base schema with writing closed.
--
-- Rules for every later migration:
--   * Tables live in public, always with RLS on (and forced). Clients get no table privileges at all: reads and writes
--     both go through `security definer` functions in public that validate the caller (app_private.me()), pin
--     `search_path` and are granted to `authenticated` only. Functions return Steam ids as text.
--   * Helpers that must not be callable from the API live in app_private (not exposed, no usage for clients).

create schema app_private;
revoke all on schema app_private from public, anon, authenticated;

-- Supabase grants everything on new tables and functions to anon/authenticated by default; close that for good.
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke execute on functions from anon, authenticated, public;
alter default privileges revoke execute on functions from public;

-- The caller's Steam id: the subject of the JWT minted by the auth-steam Edge Function. Fails closed.
create function app_private.me() returns bigint
language plpgsql stable security definer
set search_path = ''
as $$
declare
  sub text := auth.jwt() ->> 'sub';
begin
  if sub is null or sub !~ '^[0-9]{1,18}$' or coalesce(auth.jwt() ->> 'role', '') <> 'authenticated' then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  return sub::bigint;
end;
$$;

-- Name text shown to others: bidi/control characters become spaces (same idea as Wire.clean_chat on the client),
-- whitespace collapses, and it must be p_min..p_max characters long. Raises invalid_name.
create function app_private.clean_name(p_raw text, p_min int, p_max int) returns text
language plpgsql immutable
set search_path = ''
as $$
declare
  v text;
begin
  if p_raw is null or char_length(p_raw) > p_max * 4 then
    raise exception 'invalid_name';
  end if;
  v := pg_catalog.regexp_replace(p_raw, '[\x01-\x1f\x7f-\x9f؜​-‏ -‮⁠-⁩﻿]', ' ', 'g');
  v := pg_catalog.btrim(pg_catalog.regexp_replace(v, '\s+', ' ', 'g'));
  if char_length(v) < p_min or char_length(v) > p_max then
    raise exception 'invalid_name';
  end if;
  return v;
end;
$$;

create table public.players (
  steam_id bigint primary key,
  name text not null check (char_length(name) between 1 and 32),
  updated_at timestamptz not null default now()
);
alter table public.players enable row level security;
alter table public.players force row level security;

-- No policy and no grant: clients do not read tables directly. Reads are RPC functions that return Steam ids as text
-- (a Steam id does not fit in a JSON double, and Godot parses every JSON number as one).
revoke all on table public.players from anon, authenticated, public;

grant usage on schema app_private to authenticated;  -- the public functions are security definer, but keep it explicit
revoke all on function app_private.me() from public, anon;
grant execute on function app_private.me() to authenticated;
revoke all on function app_private.clean_name(text, int, int) from public, anon, authenticated;

-- Sets the caller's display name (their Steam name, sent by the client after signing in).
create function public.touch_player(p_name text) returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  me bigint := app_private.me();
  v text := app_private.clean_name(p_name, 1, 32);
begin
  insert into public.players (steam_id, name) values (me, v)
  on conflict (steam_id) do update set name = excluded.name, updated_at = now();
end;
$$;
revoke all on function public.touch_player(text) from public, anon;
grant execute on function public.touch_player(text) to authenticated;
