-- S15-S18 server side: groups with per-member confirmation, the normal queue (tickets, pairing, hidden skill) and result
-- reporting. Clients only see status, never skill; a player can never be in two matches; a falsified report changes nothing.
begin;
select no_plan();
delete from public.online_matches;
delete from public.queue_tickets;
delete from public.play_groups;
delete from public.teams;
delete from public.player_skill;
delete from public.players;

create schema t;
grant usage on schema t to anon, authenticated;
create function t.act(p_id bigint) returns void language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', p_id::text, 'role', 'authenticated')::text, true);
  set local role authenticated;
end $$;
create function t.state(p_id bigint) returns text language plpgsql as $$
declare r text;
begin
  perform t.act(p_id);
  r := public.queue_status() ->> 'state';
  return r;
end $$;
create function t.status(p_id bigint) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform t.act(p_id);
  r := public.queue_status();
  return r;
end $$;
create function t.clear_rate() returns void language sql security definer set search_path = '' as $$ delete from public.rate_limits $$;
create function t.age(p_id bigint, p_secs int) returns void language sql security definer set search_path = '' as $$
  update public.queue_tickets set created_at = created_at - make_interval(secs => p_secs)
   where id = (select ticket_id from public.ticket_members where steam_id = p_id) $$;
create function t.stale(p_id bigint) returns void language sql security definer set search_path = '' as $$
  update public.ticket_members set last_poll = now() - interval '3 minutes' where steam_id = p_id $$;
create function t.skill(p_id bigint, p_mode int) returns int language sql security definer set search_path = '' as $$
  select skill from public.player_skill where steam_id = p_id and mode = p_mode $$;
create function t.games(p_id bigint, p_mode int) returns int language sql security definer set search_path = '' as $$
  select games from public.player_skill where steam_id = p_id and mode = p_mode $$;
create function t.set_skill(p_id bigint, p_mode int, p_v int) returns void language sql security definer set search_path = '' as $$
  insert into public.player_skill (steam_id, mode, skill, games) values (p_id, p_mode, p_v, 10)
  on conflict (steam_id, mode) do update set skill = excluded.skill, games = excluded.games $$;
create function t.match_of(p_id bigint) returns uuid language sql security definer set search_path = '' as $$
  select match_id from public.online_match_players where steam_id = p_id and active $$;
create function t.any_match_of(p_id bigint) returns uuid language sql security definer set search_path = '' as $$
  select match_id from public.online_match_players where steam_id = p_id order by created_at desc limit 1 $$;
create function t.side_of(p_id bigint) returns text language sql security definer set search_path = '' as $$
  select side from public.online_match_players where steam_id = p_id and active $$;
create function t.age_match(p_match uuid, p_secs int) returns void language sql security definer set search_path = '' as $$
  update public.online_matches set created_at = created_at - make_interval(secs => p_secs) where id = p_match $$;
create function t.match_status(p_match uuid) returns text language sql security definer set search_path = '' as $$
  select status from public.online_matches where id = p_match $$;
create function t.n_matches() returns int language sql security definer set search_path = '' as $$
  select count(*)::int from public.online_matches $$;
create function t.make_team(p_captain bigint, p_name text, p_mode int) returns uuid language plpgsql as $$
declare v uuid;
begin
  perform t.act(p_captain);
  v := public.create_team(p_mode, p_name);
  return v;
end $$;
create function t.add_to_team(p_team uuid, p_captain bigint, p_member bigint) returns void language plpgsql as $$
declare v uuid;
begin
  perform t.act(p_captain);
  perform public.invite_to_team(p_team, p_member);
  perform t.act(p_member);
  perform public.accept_invite((select (i ->> 'id')::uuid from jsonb_array_elements(public.my_invites()) i limit 1));
end $$;
grant execute on all functions in schema t to anon, authenticated;

-- players 8001..8012
do $$ begin
  for i in 1..12 loop
    perform t.act(8000 + i);
    perform public.touch_player('P' || i);
  end loop;
end $$;

-- ---------------------------------------------------------------- shape and privileges
select has_table('public', 'play_groups', 'tabla play_groups');
select has_table('public', 'queue_tickets', 'tabla queue_tickets');
select has_table('public', 'online_matches', 'tabla online_matches');
select has_table('public', 'player_skill', 'tabla player_skill (habilidad oculta)');
reset role;
select is((select count(*)::int from information_schema.role_table_grants
            where table_schema = 'public' and grantee in ('anon', 'authenticated', 'PUBLIC')
              and table_name in ('play_groups', 'play_group_members', 'queue_tickets', 'ticket_members', 'online_matches',
                                 'online_match_players', 'online_match_reports', 'player_skill', 'rate_limits')),
  0, 'ningun cliente tiene privilegios sobre las tablas de cola, partidas y habilidad');
select ok(not has_table_privilege('authenticated', 'public.player_skill', 'SELECT'), 'la habilidad no se lee directo');
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.prokind = 'f' and pg_get_function_result(p.oid) ~* 'player_skill'),
  0, 'ninguna funcion devuelve filas de player_skill');
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.prokind = 'f' and p.proname ~* '(skill|rating|mmr|elo)'),
  0, 'ninguna RPC publica se llama skill/rating/mmr/elo');
select ok(exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'online_match_players_one_active'
                   and indexdef ~* 'unique' and indexdef ~* 'where'), 'indice unico parcial: un jugador, una partida activa');
select t.act(8001);
select throws_ok($$select * from public.player_skill$$, '42501', null, 'no se lee player_skill');
select throws_ok($$select * from public.queue_tickets$$, '42501', null, 'no se lee queue_tickets');
select throws_ok($$update public.player_skill set skill = 3000$$, '42501', null, 'no se escribe player_skill');
reset role;
set local role anon;
select throws_ok($$select public.queue_status()$$, '42501', null, 'anon no ejecuta queue_status');
select throws_ok($$select public.join_queue(1, 'v')$$, '42501', null, 'anon no ejecuta join_queue');
reset role;

-- ---------------------------------------------------------------- groups
select t.act(8001);
select throws_ok($$select public.create_group(1)$$, 'P0001', 'invalid_mode', 'los grupos son de 2 o 3');
select throws_ok($$select public.create_group(4)$$, 'P0001', 'invalid_mode', 'no hay grupos de 4');
select lives_ok($$select public.create_group(2)$$, 'Ana crea un grupo 2v2');
select throws_ok($$select public.create_group(3)$$, 'P0001', 'already_in_group', 'un grupo a la vez');
select is((public.my_group() ->> 'leader'), '8001', 'el lider es Ana (id como texto)');
select is(jsonb_array_length(public.my_group() -> 'members'), 1, 'un integrante');
select is((public.my_group() -> 'members' -> 0 ->> 'confirmed')::boolean, true, 'el lider esta confirmado');
select throws_ok($$select public.group_add((public.my_group() ->> 'id')::uuid, 8001)$$, 'P0001', 'invalid_target', 'no te invitas a vos');
select lives_ok($$select public.group_add((public.my_group() ->> 'id')::uuid, 8002)$$, 'invita a Beto');
select throws_ok($$select public.group_add((public.my_group() ->> 'id')::uuid, 8003)$$, 'P0001', 'group_full', 'el grupo 2v2 admite 2 con los pendientes');
select throws_ok($$select public.join_queue(2, 'v1', (public.my_group() ->> 'id')::uuid)$$, 'P0001', 'not_confirmed', 'no se busca sin que todos confirmen');
select t.act(8002);
select is(jsonb_array_length(public.my_group_invites()), 1, 'Beto ve la invitacion del grupo');
select is((public.my_group_invites() -> 0 ->> 'from'), '8001', 'invita Ana');
select is(public.my_group() , null, 'sin confirmar no tiene grupo propio');
select throws_ok($$select public.group_confirm(gen_random_uuid())$$, 'P0001', 'group_not_found', 'grupo inexistente');
select lives_ok($$select public.group_confirm((public.my_group_invites() -> 0 ->> 'id')::uuid)$$, 'Beto confirma');
select is((public.my_group() ->> 'leader'), '8001', 'Beto ve su grupo');
select throws_ok($$select public.create_group(2)$$, 'P0001', 'already_in_group', 'ya esta en un grupo');
select throws_ok($$select public.group_add((public.my_group() ->> 'id')::uuid, 8003)$$, 'P0001', 'not_leader', 'solo el lider invita');
select lives_ok($$select public.leave_group((public.my_group() ->> 'id')::uuid)$$, 'Beto se va');
select t.act(8001);
select is(jsonb_array_length(public.my_group() -> 'members'), 1, 'el grupo volvio a uno');
select lives_ok($$select public.group_add((public.my_group() ->> 'id')::uuid, 8002)$$, 're-invita a Beto');
select t.act(8002);
select lives_ok($$select public.group_decline((public.my_group_invites() -> 0 ->> 'id')::uuid)$$, 'Beto rechaza');
select is(jsonb_array_length(public.my_group_invites()), 0, 'sin invitaciones');
select t.act(8001);
select lives_ok($$select public.leave_group((public.my_group() ->> 'id')::uuid)$$, 'la lider se va: se disuelve');
select is(public.my_group(), null, 'sin grupo');

-- team group: only the captain, only for members of the team of that mode
reset role;
reset role;
create function t.team(p_name text, p_mode int default 2) returns uuid language sql security definer set search_path = '' as $$
  select id from public.teams where name = p_name and mode = p_mode $$;
grant execute on function t.team(text, int) to anon, authenticated;
select t.make_team(8001, 'Lobos', 2);
select t.add_to_team(t.team('Lobos'), 8001, 8002);
select t.make_team(8003, 'Cuervos', 2);
select t.add_to_team(t.team('Cuervos'), 8003, 8004);
select t.act(8001);
select throws_ok($$select public.create_group(3, t.team('Lobos'))$$, 'P0001', 'invalid_mode', 'el equipo es de otra modalidad');
select throws_ok($$select public.create_group(2, t.team('Cuervos'))$$, 'P0001', 'not_captain', 'solo el capitan arma el grupo del equipo');
select lives_ok($$select public.create_group(2, t.team('Lobos'))$$, 'la capitana arma el grupo del equipo');
select throws_ok($$select public.group_add((public.my_group() ->> 'id')::uuid, 8005)$$, 'P0001', 'not_member', 'un grupo de equipo solo admite integrantes del equipo');
select lives_ok($$select public.group_add((public.my_group() ->> 'id')::uuid, 8002)$$, 'invita a su companero');
select t.act(8002);
select lives_ok($$select public.group_confirm((public.my_group_invites() -> 0 ->> 'id')::uuid)$$, 'el companero confirma');
select t.act(8001);
select lives_ok($$select public.leave_group((public.my_group() ->> 'id')::uuid)$$, 'disolver el grupo de equipo');
select is(public.my_group(), null, 'y ya no hay grupo');
select t.clear_rate();

-- ---------------------------------------------------------------- 1v1 queue
select t.act(8001);
select throws_ok($$select public.join_queue(4, '0.7.0')$$, 'P0001', 'invalid_mode', 'modo invalido');
select throws_ok($$select public.join_queue(1, '')$$, 'P0001', 'invalid_version', 'version vacia');
select throws_ok($$select public.join_queue(1, repeat('x', 41))$$, 'P0001', 'invalid_version', 'version demasiado larga');
select lives_ok($$select public.join_queue(1, '0.7.0')$$, 'Ana entra a la cola 1v1');
select is(t.state(8001), 'searching', 'Ana busca');
select is((t.status(8001) ->> 'searching')::int, 1, 'una persona buscando');
select throws_ok($$select public.join_queue(1, '0.7.0')$$, 'P0001', 'already_queued', 'no se entra dos veces a la cola');
select t.act(8002);
select lives_ok($$select public.join_queue(1, '0.7.1')$$, 'Beto con otra version');
select is(t.state(8001), 'searching', 'otra version no empareja (Ana)');
select is(t.state(8002), 'searching', 'otra version no empareja (Beto)');
select t.act(8002);
select lives_ok($$select public.leave_queue()$$, 'Beto sale');
select is(t.state(8002), 'idle', 'Beto queda ocioso');
select t.act(8003);
select lives_ok($$select public.join_queue(2, '0.7.0')$$, 'Caro busca 2v2');
select is(t.state(8001), 'searching', 'otra modalidad no empareja');
select t.act(8003);
select public.leave_queue();
-- skills far apart do not match at once, but do after waiting
select t.set_skill(8001, 1, 1500);
select t.set_skill(8002, 1, 2000);
select t.act(8002);
select public.join_queue(1, '0.7.0');
select is(t.state(8001), 'searching', 'habilidades lejanas: todavia no (Ana)');
select is(t.state(8002), 'searching', 'habilidades lejanas: todavia no (Beto)');
select t.age(8001, 40);
select t.age(8002, 40);
select is(t.state(8001), 'matched', 'tras esperar se ensancha la ventana: Ana empareja');
select is(t.state(8002), 'matched', 'y Beto tambien');
select isnt(t.match_of(8001), null, 'hay partida');
select is(t.match_of(8001), t.match_of(8002), 'los dos en la misma partida');
select isnt(t.side_of(8001), t.side_of(8002), 'lados distintos en 1v1');
select is((t.status(8001) -> 'match' ->> 'is_host')::boolean <> (t.status(8002) -> 'match' ->> 'is_host')::boolean, true, 'un solo anfitrion');
select is(t.status(8001) -> 'match' -> 'lobby_id', 'null'::jsonb, 'aun sin id de sala');
select is(position('skill' in lower(t.status(8001)::text)) + position('mmr' in lower(t.status(8001)::text)) + position('rating' in lower(t.status(8001)::text)), 0, 'el estado no contiene habilidad');
select is(t.status(8001) -> 'match' -> 'sides' -> 'red' -> 0 ->> 'steam_id' ~ '^[0-9]+$', true, 'ids como texto en los lados');
select t.act(8001);
select throws_ok($$select public.join_queue(1, '0.7.0')$$, 'P0001', 'already_in_match', 'quien tiene una partida activa no entra a otra');
select is(t.n_matches(), 1, 'una sola partida creada');
select t.clear_rate();

-- ---------------------------------------------------------------- lobby id
select t.act(8001);
select t.act(case when (public.queue_status() -> 'match' ->> 'is_host')::boolean then 8001 else 8002 end);
select throws_ok($$select public.publish_lobby(gen_random_uuid(), '109775241000000001')$$, 'P0001', 'not_in_match', 'partida ajena');
reset role;
create function t.host_id() returns bigint language sql security definer set search_path = '' as $$
  select host from public.online_matches order by created_at desc limit 1 $$;
create function t.guest_id() returns bigint language sql security definer set search_path = '' as $$
  select steam_id from public.online_match_players where steam_id <> t.host_id() order by created_at desc limit 1 $$;
grant execute on function t.host_id(), t.guest_id() to anon, authenticated;
select t.act(t.guest_id());
select throws_ok($$select public.publish_lobby(t.match_of(t.guest_id()), '109775241000000001')$$, 'P0001', 'not_host', 'solo el anfitrion publica la sala');
select t.act(t.host_id());
select throws_ok($$select public.publish_lobby(t.match_of(t.host_id()), 'abc')$$, 'P0001', 'invalid_lobby', 'id de sala invalido');
select throws_ok($$select public.publish_lobby(t.match_of(t.host_id()), '')$$, 'P0001', 'invalid_lobby', 'id de sala vacio');
select lives_ok($$select public.publish_lobby(t.match_of(t.host_id()), '109775241000000001')$$, 'el anfitrion publica la sala');
select is(t.status(t.guest_id()) -> 'match' ->> 'lobby_id', '109775241000000001', 'el invitado ve el id de sala (texto exacto)');

-- ---------------------------------------------------------------- results: both sides report, only if they agree
-- red won in 1v1 (both report red): hidden skill moves with the Ranked.delta formula. 1500 vs 2000, 10 games each (K = 24).
select t.set_skill(8001, 1, 1500);
select t.set_skill(8002, 1, 2000);
reset role;
create function t.red_id() returns bigint language sql security definer set search_path = '' as $$
  select steam_id from public.online_match_players where match_id = t.any_match_of(8001) and side = 'red' $$;
create function t.blue_id() returns bigint language sql security definer set search_path = '' as $$
  select steam_id from public.online_match_players where match_id = t.any_match_of(8001) and side = 'blue' $$;
grant execute on function t.red_id(), t.blue_id() to anon, authenticated;
select t.act(8003);
select throws_ok($$select public.report_result(t.match_of(8001), 'red')$$, 'P0001', 'not_in_match', 'un ajeno no informa');
select t.act(8001);
select throws_ok($$select public.report_result(t.match_of(8001), 'green')$$, 'P0001', 'invalid_winner', 'ganador invalido');
select lives_ok($$select public.report_result(t.match_of(8001), 'red')$$, 'un lado informa');
select throws_ok($$select public.report_result(t.match_of(8001), 'red')$$, 'P0001', 'already_reported', 'no se informa dos veces');
select is(t.skill(8001, 1), 1500, 'con un solo lado no cambia nada (Ana)');
select is(t.skill(8002, 1), 2000, 'con un solo lado no cambia nada (Beto)');
select t.act(8002);
select lives_ok($$select public.report_result(t.match_of(8002), 'red')$$, 'el otro lado coincide');
select is(t.match_status(t.any_match_of(8001)), 'resolved', 'la partida queda resuelta');
select is(t.skill(8001, 1), case when t.red_id() = 8001 then 1523 else 1499 end, 'habilidad de Ana: misma formula que Ranked.delta');
select is(t.skill(8002, 1), case when t.red_id() = 8001 then 1977 else 2001 end, 'habilidad de Beto: misma formula que Ranked.delta');
select is(t.games(8001, 1), 11, 'suma una partida');
select is(t.match_of(8001), null, 'ya no tienen partida activa');
select is(t.state(8001), 'idle', 'ni cola');
select t.act(8001);
select throws_ok($$select public.report_result(t.any_match_of(8001), 'blue')$$, 'P0001', 'match_closed', 'una partida resuelta no se reabre');
select t.clear_rate();

-- disagreeing reports (a falsified one): nothing changes
select t.set_skill(8001, 1, 1500);
select t.set_skill(8002, 1, 1500);
select t.act(8001);
select public.join_queue(1, '0.7.0');
select t.act(8002);
select public.join_queue(1, '0.7.0');
select is(t.state(8002), 'matched', 'otra partida 1v1');
reset role;
create function t.mid() returns uuid language sql security definer set search_path = '' as $$
  select t.any_match_of(8001) $$;
grant execute on function t.mid() to anon, authenticated;
select t.act(8001);
select public.report_result(t.mid(), 'red');
select t.act(8002);
select public.report_result(t.mid(), 'blue');
select is(t.match_status(t.mid()), 'void', 'si no coinciden la partida queda anulada');
select is(t.skill(8001, 1), 1500, 'reporte falsificado: Ana sin cambios');
select is(t.skill(8002, 1), 1500, 'reporte falsificado: Beto sin cambios');
select is(t.games(8001, 1), 10, 'y sin partida contada');
select t.clear_rate();

-- one side never reports: after the timeout nothing changes and nobody is stuck
select t.act(8001);
select public.join_queue(1, '0.7.0');
select t.act(8002);
select public.join_queue(1, '0.7.0');
select t.act(8001);
select public.report_result(t.mid(), 'red');
select t.age_match(t.mid(), 3600);
select is(t.state(8001), 'idle', 'pasado el plazo la partida pendiente se anula y no traba a nadie');
select is(t.match_status(t.mid()), 'void', 'anulada por falta de reporte');
select is(t.skill(8001, 1), 1500, 'sin reporte del otro lado no cambia nada');
select t.clear_rate();

-- someone leaves mid-match and never reports (bot or walkover): the other reports, nothing changes, nobody is blocked
select t.act(8001);
select public.join_queue(1, '0.7.0');
select t.act(8002);
select public.join_queue(1, '0.7.0');
select t.act(8002);
select lives_ok($$select public.leave_queue()$$, 'quien abandona libera su lugar');
select is(t.state(8002), 'idle', 'el que se fue puede volver a buscar');
select t.act(8001);
select public.report_result(t.mid(), 'red');
select is(t.skill(8001, 1), 1500, 'un solo lado: sin cambios');
select public.leave_queue();
select t.clear_rate();

-- a matched player whose client closed mid-match (stops polling) is released after two minutes; the other keeps the match
select t.act(8001);
select public.join_queue(1, '0.7.0');
select t.act(8002);
select public.join_queue(1, '0.7.0');
select isnt(t.match_of(8001), null, 'otra partida 1v1 para el cierre a mitad de partida');
select t.stale(8001);
select is(t.state(8002), 'matched', 'el que sigue consultando mantiene su partida');
select is(t.match_of(8001), null, 'el que dejo de consultar queda libre');
select t.act(8001);
select lives_ok($$select public.join_queue(1, '0.7.0')$$, 'y puede volver a buscar');
select public.leave_queue();
select t.act(8002);
select public.leave_queue();
select t.clear_rate();

-- ---------------------------------------------------------------- 2v2: solos fill two sides without bots; nobody twice
select t.clear_rate();
do $$ begin
  for i in 1..5 loop
    perform t.act(8000 + i);
    perform public.join_queue(2, '0.7.0');
  end loop;
end $$;
reset role;
create function t.count_state(p_state text, p_from int, p_to int) returns int language plpgsql as $$
declare n int := 0;
begin
  for i in p_from..p_to loop
    if t.state(8000 + i) = p_state then n := n + 1; end if;
  end loop;
  return n;
end $$;
grant execute on function t.count_state(text, int, int) to anon, authenticated;
reset role;
create function t.n_active_players() returns int language sql security definer set search_path = '' as $$
  select count(*)::int from public.online_match_players where active $$;
create function t.max_matches_per_player() returns int language sql security definer set search_path = '' as $$
  select coalesce(max(c), 0)::int from (select count(*) c from public.online_match_players where active group by steam_id) q $$;
create function t.sides_ok(p_mode int) returns boolean language sql security definer set search_path = '' as $$
  select coalesce(bool_and(r = p_mode and b = p_mode), false) from (
    select match_id, count(*) filter (where side = 'red') r, count(*) filter (where side = 'blue') b
      from public.online_match_players where active group by match_id) q $$;
grant execute on function t.n_active_players(), t.max_matches_per_player(), t.sides_ok(int) to anon, authenticated;
select is(t.count_state('matched', 1, 5), 4, '5 solos en 2v2: se forman 4 emparejados');
select is(t.count_state('searching', 1, 5), 1, 'y uno sigue buscando (sin bots)');
select is(t.n_active_players(), 4, 'cuatro jugadores activos en partidas');
select is(t.max_matches_per_player(), 1, 'nadie esta en dos partidas');
select is(t.sides_ok(2), true, 'dos de cada lado');
-- the fifth one keeps polling and is still alone: polling again never steals players from the formed match
select t.act(8005);
select is(public.queue_status() ->> 'state', 'searching', 'el quinto sigue solo aunque consulte de nuevo');
select is(t.max_matches_per_player(), 1, 'consultar no rehace emparejamientos');
select t.clear_rate();
-- clean up: everyone out
do $$ begin
  for i in 1..12 loop perform t.act(8000 + i); perform public.leave_queue(); end loop;
end $$;
select is(t.n_active_players(), 0, 'todos libres');
select t.clear_rate();

-- 2v2 with a team and two solos: the team stays on one side
select t.act(8001);
select public.create_group(2, t.team('Lobos'));
select public.group_add((public.my_group() ->> 'id')::uuid, 8002);
select t.act(8002);
select public.group_confirm((public.my_group_invites() -> 0 ->> 'id')::uuid);
select t.act(8001);
select lives_ok($$select public.join_queue(2, '0.7.0', (public.my_group() ->> 'id')::uuid)$$, 'el equipo busca como grupo');
select is(t.state(8002), 'searching', 'el companero tambien figura buscando');
select t.act(8002);
select throws_ok($$select public.join_queue(2, '0.7.0')$$, 'P0001', 'already_queued', 'el integrante no puede buscar aparte');
select t.act(8003);
select public.join_queue(2, '0.7.0');
select is(t.state(8003), 'searching', 'con un solo rival no alcanza');
select t.act(8004);
select public.join_queue(2, '0.7.0');
select is(t.state(8001), 'matched', 'equipo + dos solos: arma partida');
select is(t.side_of(8001), t.side_of(8002), 'los integrantes del equipo quedan del mismo lado');
select isnt(t.side_of(8001), t.side_of(8003), 'los solos enfrentan al equipo');
select is(t.side_of(8003), t.side_of(8004), 'los dos solos juntos');
select is(t.sides_ok(2), true, 'dos de cada lado');
select t.act(8001);
select public.leave_queue();
select t.act(8002);
select public.leave_queue();
select t.act(8003);
select public.leave_queue();
select t.act(8004);
select public.leave_queue();
select t.act(8001);
select public.leave_group((public.my_group() ->> 'id')::uuid);
select t.clear_rate();

-- 3v3: a group of 3 and a solo + a pair, and mixed sizes that cannot fill two sides stay waiting
select t.act(8001);
select public.create_group(3);
select public.group_add((public.my_group() ->> 'id')::uuid, 8002);
select public.group_add((public.my_group() ->> 'id')::uuid, 8003);
select t.act(8002);
select public.group_confirm((public.my_group_invites() -> 0 ->> 'id')::uuid);
select t.act(8003);
select public.group_confirm((public.my_group_invites() -> 0 ->> 'id')::uuid);
select t.act(8001);
select public.join_queue(3, '0.7.0', (public.my_group() ->> 'id')::uuid);
select t.act(8004);
select public.join_queue(3, '0.7.0');
select t.act(8005);
select public.join_queue(3, '0.7.0');
select is(t.state(8001), 'searching', '3 + 1 + 1: falta uno para el otro lado');
select t.act(8006);
select public.join_queue(3, '0.7.0');
select is(t.state(8001), 'matched', '3 + 1 + 1 + 1: 3v3 completo');
select is(t.side_of(8001), t.side_of(8003), 'el grupo de 3 junto');
select is(t.sides_ok(3), true, 'tres de cada lado');
do $$ begin
  for i in 1..12 loop perform t.act(8000 + i); perform public.leave_queue(); end loop;
end $$;
select t.act(8001);
select public.leave_group((public.my_group() ->> 'id')::uuid);
select t.clear_rate();

-- ---------------------------------------------------------------- expiry: a player who stops polling is dropped
select t.act(8007);
select public.join_queue(1, '0.7.0');
select t.stale(8007);
select t.act(8008);
select public.join_queue(1, '0.7.0');
select is(t.state(8008), 'searching', 'un ticket vencido (sin consultas) no empareja');
select is(t.state(8007), 'idle', 'y se descarta');
select t.act(8008);
select public.leave_queue();
select t.clear_rate();

-- ---------------------------------------------------------------- team history after a resolved match, no rating anywhere
select t.act(8001);
select public.create_group(2, t.team('Lobos'));
select public.group_add((public.my_group() ->> 'id')::uuid, 8002);
select t.act(8002);
select public.group_confirm((public.my_group_invites() -> 0 ->> 'id')::uuid);
select t.act(8001);
select public.join_queue(2, '0.7.0', (public.my_group() ->> 'id')::uuid);
select t.act(8003);
select public.join_queue(2, '0.7.0');
select t.act(8004);
select public.join_queue(2, '0.7.0');
select t.act(8009);
select public.join_queue(2, '0.7.0');
select is(t.state(8001), 'matched', 'partida para el historial');
reset role;
create function t.hid() returns uuid language sql security definer set search_path = '' as $$ select t.any_match_of(8001) $$;
grant execute on function t.hid() to anon, authenticated;
select t.act(8001);
select public.report_result(t.hid(), t.side_of(8001));
select t.act(8003);
select public.report_result(t.hid(), (select case when t.side_of(8001) = 'red' then 'red' else 'blue' end));
select is(t.match_status(t.hid()), 'resolved', 'resuelta');
select t.act(8002);
select is(jsonb_array_length(public.team_history(t.team('Lobos'))), 1, 'el equipo ve su historial');
select is((public.team_history(t.team('Lobos')) -> 0 ->> 'won')::boolean, true, 'ganaron');
select is(position('skill' in lower(public.team_history(t.team('Lobos'))::text)) + position('rating' in lower(public.team_history(t.team('Lobos'))::text)), 0, 'el historial no muestra habilidad');
select t.act(8005);
select throws_ok($$select public.team_history(t.team('Lobos'))$$, 'P0001', 'not_member', 'un ajeno no ve el historial');
select t.clear_rate();

-- ---------------------------------------------------------------- rate limiting
select t.act(8010);
do $$ declare ok_n int := 0; begin
  for i in 1..10 loop
    perform public.join_queue(1, '0.7.0');
    perform public.leave_queue();
    ok_n := ok_n + 1;
  end loop;
end $$;
select throws_ok($$select public.join_queue(1, '0.7.0')$$, 'P0001', 'rate_limited', 'join_queue tiene tope por jugador');
select t.act(8011);
select lives_ok($$select public.join_queue(1, '0.7.0')$$, 'otro jugador no se ve afectado');
select public.leave_queue();
select t.clear_rate();
reset role;
create function t.purge_group(p_group uuid) returns void language sql security definer set search_path = '' as $$
  delete from public.play_group_members where group_id = p_group and steam_id <> (select leader from public.play_groups where id = p_group) $$;
create function t.purge_invites(p_team uuid) returns void language sql security definer set search_path = '' as $$
  delete from public.team_invites where team_id = p_team $$;
grant execute on function t.purge_group(uuid), t.purge_invites(uuid) to anon, authenticated;
select t.act(8012);
select public.create_group(3);
do $$ begin
  for i in 1..19 loop
    perform public.group_add((public.my_group() ->> 'id')::uuid, 8100 + i);
    perform t.purge_group((public.my_group() ->> 'id')::uuid);
  end loop;
end $$;
select throws_ok($$select public.group_add((public.my_group() ->> 'id')::uuid, 8200)$$, 'P0001', 'rate_limited', 'group_add tiene tope (20 por minuto con el create_group)');
select t.clear_rate();
select t.act(8001);
do $$ begin
  for i in 1..20 loop
    perform public.invite_to_team(t.team('Lobos'), 8300 + i);
    perform t.purge_invites(t.team('Lobos'));
  end loop;
end $$;
select throws_ok($$select public.invite_to_team(t.team('Lobos'), 8999)$$, 'P0001', 'rate_limited', 'invite_to_team tiene tope');
select t.clear_rate();

select * from finish();
rollback;
