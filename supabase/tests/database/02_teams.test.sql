-- S14: persistent teams on the server. Every rule is enforced by the RPC functions, never by the client.
begin;
select no_plan();
delete from public.teams;    -- the database may hold data from manual runs; this transaction is rolled back
delete from public.players;

-- Test helpers (rolled back with the transaction): act as a player, and look a team up by name.
create schema t;
grant usage on schema t to anon, authenticated;
create function t.act(p_id bigint) returns void language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', p_id::text, 'role', 'authenticated')::text, true);
  set local role authenticated;
end $$;
create function t.team(p_name text, p_mode int default 2) returns uuid language sql security definer set search_path = '' as $$
  select id from public.teams where name = p_name and mode = p_mode $$;
create function t.members(p_name text, p_mode int default 2) returns bigint[] language sql security definer set search_path = '' as $$
  select coalesce(array_agg(steam_id order by steam_id), '{}') from public.team_members where team_id = t.team(p_name, p_mode) $$;
create function t.pending(p_name text, p_mode int default 2) returns int language sql security definer set search_path = '' as $$
  select count(*)::int from public.team_invites where team_id = t.team(p_name, p_mode) $$;
create function t.captain(p_name text, p_mode int default 2) returns bigint language sql security definer set search_path = '' as $$
  select captain from public.teams where name = p_name and mode = p_mode $$;
create function t.invite_of(p_to bigint) returns uuid language sql security definer set search_path = '' as $$
  select id from public.team_invites where to_steam = p_to limit 1 $$;
grant execute on all functions in schema t to anon, authenticated;

-- ---------------------------------------------------------------- shape
select has_table('public', 'teams', 'tabla teams');
select has_table('public', 'team_members', 'tabla team_members');
select has_table('public', 'team_invites', 'tabla team_invites');
select is((select count(*)::int from information_schema.columns
            where table_schema = 'public' and table_name in ('teams', 'team_members', 'team_invites', 'players')
              and column_name ~* '(rating|elo|mmr|league|points|score|rank)'),
  0, 'los equipos no tienen columnas de rating');

-- ---------------------------------------------------------------- no direct access
select t.act(7001);
select throws_ok($$select * from public.teams$$, '42501', null, 'no se lee teams directo');
select throws_ok($$select * from public.team_members$$, '42501', null, 'no se lee team_members directo');
select throws_ok($$select * from public.team_invites$$, '42501', null, 'no se lee team_invites directo');
select throws_ok($$insert into public.teams (mode, name, name_key, captain) values (2, 'Hack', 'hack', 7001)$$, '42501', null, 'no se inserta en teams');
select throws_ok($$insert into public.team_members (team_id, mode, steam_id) values (gen_random_uuid(), 2, 7001)$$, '42501', null, 'no se inserta en team_members');
select throws_ok($$insert into public.team_invites (team_id, mode, from_steam, to_steam) values (gen_random_uuid(), 2, 7001, 7002)$$, '42501', null, 'no se inserta en team_invites');
select throws_ok($$update public.teams set captain = 7001$$, '42501', null, 'no se actualiza teams');
select throws_ok($$delete from public.team_members$$, '42501', null, 'no se borra de team_members');
reset role;
set local role anon;
select throws_ok($$select public.create_team(2, 'Anon')$$, '42501', null, 'anon no ejecuta create_team');
select throws_ok($$select public.my_teams()$$, '42501', null, 'anon no ejecuta my_teams');
select throws_ok($$select public.disband_team(gen_random_uuid())$$, '42501', null, 'anon no ejecuta disband_team');
reset role;

-- ---------------------------------------------------------------- create
select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
set local role authenticated;
select throws_ok($$select public.create_team(2, 'Sin sub')$$, '28000', 'not_authenticated', 'sin sujeto no hay equipo');

select t.act(7001);
select public.touch_player('Ana');
select throws_ok($$select public.create_team(1, 'Solitos')$$, 'P0001', 'invalid_mode', '1v1 no tiene equipos');
select throws_ok($$select public.create_team(4, 'Cuatro')$$, 'P0001', 'invalid_mode', '4v4 tampoco');
select throws_ok($$select public.create_team(2, 'ab')$$, 'P0001', 'invalid_name', 'nombre demasiado corto');
select throws_ok($$select public.create_team(2, repeat('x', 21))$$, 'P0001', 'invalid_name', 'nombre de 21 caracteres');
select throws_ok($$select public.create_team(2, E'\u202e \u2066')$$, 'P0001', 'invalid_name', 'nombre solo de controles bidi');
select throws_ok($$select public.create_team(2, null)$$, 'P0001', 'invalid_name', 'nombre nulo');
select lives_ok($$select public.create_team(2, E'Los\u202e   Lobos ')$$, 'Ana crea un 2v2');
reset role;
select is(t.captain('Los Lobos'), 7001::bigint, 'el capitan es quien lo creo; nombre sin bidi ni espacios dobles');
select is(t.members('Los Lobos'), array[7001::bigint], 'la capitana es integrante');

select t.act(7001);
select throws_ok($$select public.create_team(2, 'Otro 2v2')$$, 'P0001', 'already_in_team', 'un equipo por modalidad');
select lives_ok($$select public.create_team(3, 'Los Lobos')$$, 'si en otra modalidad, incluso con el mismo nombre');
select t.act(7003);
select public.touch_player('Caro');
select throws_ok($$select public.create_team(2, 'LOS   lobos')$$, 'P0001', 'name_taken', 'nombre unico por modalidad, sin importar mayusculas ni espacios');
select lives_ok($$select public.create_team(2, 'Cuervos')$$, 'Caro crea su propio 2v2');

-- ---------------------------------------------------------------- invite
select t.act(7001);
select throws_ok($$select public.invite_to_team(gen_random_uuid(), 7002)$$, 'P0001', 'team_not_found', 'equipo inexistente');
select throws_ok($$select public.invite_to_team(t.team('Los Lobos'), 7001)$$, 'P0001', 'invalid_target', 'no se invita a uno mismo');
select throws_ok($$select public.invite_to_team(t.team('Los Lobos'), 0)$$, 'P0001', 'invalid_target', 'id invalido');
select throws_ok($$select public.invite_to_team(t.team('Los Lobos'), 7003)$$, 'P0001', 'already_in_team', 'quien ya tiene equipo 2v2 no se invita');
select lives_ok($$select public.invite_to_team(t.team('Los Lobos'), 7002)$$, 'Ana invita a Beto, que ni abrio el juego todavia');
select throws_ok($$select public.invite_to_team(t.team('Los Lobos'), 7002)$$, 'P0001', 'already_invited', 'una invitacion por jugador y equipo');
select t.act(7004);
select throws_ok($$select public.invite_to_team(t.team('Los Lobos'), 7005)$$, 'P0001', 'not_captain', 'un ajeno no invita a un equipo que no es suyo');
select throws_ok($$select public.cancel_invite((select (public.my_invites() -> 0 ->> 'id')::uuid))$$, 'P0001', 'invite_not_found', 'Dani no ve invitaciones ajenas');
select is(public.my_invites(), '[]'::jsonb, 'Dani no tiene invitaciones');
select is(public.my_teams(), '[]'::jsonb, 'Dani no tiene equipos');

select t.act(7002);
select is(jsonb_array_length(public.my_invites()), 1, 'Beto ve su invitacion aunque no estaba conectado');
select is(public.my_invites() -> 0 ->> 'team_name', 'Los Lobos', 'con el nombre del equipo');
select is(public.my_invites() -> 0 ->> 'from', '7001', 'y quien lo invito, como texto');
select is(public.my_invites() -> 0 ->> 'mode', '2', 'y la modalidad');
select throws_ok($$select public.invite_to_team(t.team('Los Lobos'), 7005)$$, 'P0001', 'not_captain', 'ni siquiera con invitacion pendiente es capitan');

-- ---------------------------------------------------------------- accept, decline, cancel
select t.act(7003);
select throws_ok($$select public.accept_invite((select id from public.team_invites limit 1))$$, '42501', null, 'Caro no puede mirar la tabla para sacar ids');
select throws_ok($$select public.accept_invite(gen_random_uuid())$$, 'P0001', 'invite_not_found', 'invitacion inexistente');
reset role;
select is((select count(*)::int from public.team_invites where to_steam = 7002), 1, 'la invitacion de Beto existe');
select t.act(7003);
select throws_ok(format($$select public.accept_invite(%L)$$, t.invite_of(7002)), 'P0001', 'invite_not_found', 'Caro no acepta la invitacion de Beto');
select throws_ok(format($$select public.decline_invite(%L)$$, t.invite_of(7002)), 'P0001', 'invite_not_found', 'ni la rechaza');
select t.act(7002);
select lives_ok($$select public.accept_invite((public.my_invites() -> 0 ->> 'id')::uuid)$$, 'Beto acepta');
select public.touch_player('Beto');
reset role;
select is(t.members('Los Lobos'), array[7001::bigint, 7002], 'ahora son Ana y Beto');
select is(t.pending('Los Lobos'), 0, 'la invitacion se consumio');

select t.act(7002);
select is(jsonb_array_length(public.my_teams()), 1, 'Beto ve su equipo');
select is(public.my_teams() -> 0 ->> 'name', 'Los Lobos', 'nombre');
select is(public.my_teams() -> 0 ->> 'captain', '7001', 'capitan como texto');
select is(jsonb_array_length(public.my_teams() -> 0 -> 'members'), 2, 'con sus dos integrantes');
select is(public.my_teams() -> 0 -> 'members' -> 0 ->> 'name', 'Ana', 'con nombres');
select is((public.my_teams() -> 0 -> 'members' -> 0 -> 'captain')::text, 'true', 'marcando al capitan');
select throws_ok($$select public.accept_invite(gen_random_uuid())$$, 'P0001', 'invite_not_found', 'otra vez, nada');

-- A second invite to someone who is already taken by another team of that mode fails on accept, and accepting
-- one team drops the player's other pending invites of that mode.
select t.act(7003);
select lives_ok($$select public.invite_to_team(t.team('Cuervos'), 7004)$$, 'Caro invita a Dani');
select t.act(7001);
select lives_ok($$select public.invite_to_team(t.team('Los Lobos'), 7004)$$, 'Ana tambien invita a Dani');
select t.act(7004);
select is(jsonb_array_length(public.my_invites()), 2, 'Dani tiene dos invitaciones');
select lives_ok($$select public.accept_invite((select (i ->> 'id')::uuid from jsonb_array_elements(public.my_invites()) i where i ->> 'team_name' = 'Cuervos'))$$, 'Dani acepta Cuervos');
select is(public.my_invites(), '[]'::jsonb, 'su otra invitacion 2v2 desaparecio');
reset role;
select is(t.members('Los Lobos'), array[7001::bigint, 7002], 'Los Lobos no ganaron a Dani');
select is(t.pending('Los Lobos'), 0, 'y no les quedo pendiente');

-- decline / cancel
select t.act(7001);
select lives_ok($$select public.invite_to_team(t.team('Los Lobos'), 7005)$$, 'Ana invita a 7005');
select t.act(7005);
select lives_ok($$select public.decline_invite((public.my_invites() -> 0 ->> 'id')::uuid)$$, '7005 rechaza');
select is(public.my_invites(), '[]'::jsonb, 'ya no la tiene');
select t.act(7001);
select lives_ok($$select public.invite_to_team(t.team('Los Lobos'), 7005)$$, 'se puede volver a invitar');
reset role;
select is(t.pending('Los Lobos'), 1, 'pendiente');
select t.act(7002);
select throws_ok(format($$select public.cancel_invite(%L)$$, t.invite_of(7005)), 'P0001', 'not_captain', 'solo el capitan cancela');
select t.act(7001);
select lives_ok(format($$select public.cancel_invite(%L)$$, t.invite_of(7005)), 'la capitana cancela');
reset role;
select is(t.pending('Los Lobos'), 0, 'cancelada');

-- expired invites are not invites
select t.act(7001);
select public.invite_to_team(t.team('Los Lobos'), 7006);
reset role;
update public.team_invites set expires_at = now() - interval '1 minute' where to_steam = 7006;
select t.act(7006);
select is(public.my_invites(), '[]'::jsonb, 'una invitacion vencida no se muestra');
select throws_ok(format($$select public.accept_invite(%L)$$, t.invite_of(7006)), 'P0001', 'invite_not_found', 'ni se acepta');

-- ---------------------------------------------------------------- capacity (mode * 2 members, pending invites count)
select t.act(7001);
select lives_ok($$select public.invite_to_team(t.team('Los Lobos'), 7007)$$, 'tercera plaza (2v2 admite 4)');
select lives_ok($$select public.invite_to_team(t.team('Los Lobos'), 7008)$$, 'cuarta plaza: integrantes + pendientes = 4');
select throws_ok($$select public.invite_to_team(t.team('Los Lobos'), 7009)$$, 'P0001', 'team_full', 'quinta: no entra');
select t.act(7007);
select lives_ok($$select public.accept_invite((public.my_invites() -> 0 ->> 'id')::uuid)$$, '7007 entra');
select t.act(7008);
select lives_ok($$select public.accept_invite((public.my_invites() -> 0 ->> 'id')::uuid)$$, '7008 entra');
reset role;
select is(cardinality(t.members('Los Lobos')), 4, 'cuatro integrantes');
-- 3v3 admits 6; fill with direct inserts as the owner, then the client path refuses the seventh.
insert into public.teams (id, mode, name, name_key, captain) values ('00000000-0000-0000-0000-0000000000a3', 3, 'Seis', 'seis', 7101);
insert into public.team_members (team_id, mode, steam_id)
  select '00000000-0000-0000-0000-0000000000a3', 3, g from generate_series(7101, 7106) g;
select t.act(7101);
select throws_ok($$select public.invite_to_team('00000000-0000-0000-0000-0000000000a3', 7107)$$, 'P0001', 'team_full', '3v3 lleno con 6');
-- accept path re-checks capacity (invite created while there was room)
reset role;
insert into public.team_invites (team_id, mode, from_steam, to_steam) values ('00000000-0000-0000-0000-0000000000a3', 3, 7101, 7107);
select t.act(7107);
select throws_ok($$select public.accept_invite((public.my_invites() -> 0 ->> 'id')::uuid)$$, 'P0001', 'team_full', 'aceptar tampoco pasa el limite');
-- a player who joined another team of the mode meanwhile cannot accept
reset role;
insert into public.team_invites (team_id, mode, from_steam, to_steam) values (t.team('Los Lobos'), 2, 7001, 7003);
select t.act(7003);
select throws_ok($$select public.accept_invite((public.my_invites() -> 0 ->> 'id')::uuid)$$, 'P0001', 'already_in_team', 'ya tiene equipo 2v2');
-- invitee inbox is bounded
reset role;
insert into public.teams (id, mode, name, name_key, captain)
  select ('00000000-0000-0000-0000-00000000' || lpad(g::text, 4, '0'))::uuid, 2, 'Spam ' || g, 'spam ' || g, 8000 + g from generate_series(1, 21) g;
insert into public.team_members (team_id, mode, steam_id)
  select ('00000000-0000-0000-0000-00000000' || lpad(g::text, 4, '0'))::uuid, 2, 8000 + g from generate_series(1, 21) g;
insert into public.team_invites (team_id, mode, from_steam, to_steam)
  select ('00000000-0000-0000-0000-00000000' || lpad(g::text, 4, '0'))::uuid, 2, 8000 + g, 9999 from generate_series(2, 21) g;
select t.act(8001);
select throws_ok($$select public.invite_to_team(t.team('Spam 1'), 9999)$$, 'P0001', 'invitee_inbox_full', 'la bandeja de un jugador tiene tope');

-- ---------------------------------------------------------------- leave, kick, transfer, disband
select t.act(7001);
select throws_ok($$select public.leave_team(t.team('Los Lobos'))$$, 'P0001', 'captain_must_transfer_or_disband', 'la capitana no se va sin traspasar o disolver');
select throws_ok($$select public.leave_team(t.team('Cuervos'))$$, 'P0001', 'not_member', 'ni se va de un equipo ajeno');
select t.act(7007);
select throws_ok($$select public.kick_member(t.team('Los Lobos'), 7008)$$, 'P0001', 'not_captain', 'un integrante no expulsa');
select throws_ok($$select public.transfer_captain(t.team('Los Lobos'), 7007)$$, 'P0001', 'not_captain', 'ni se traspasa la capitania a si mismo');
select throws_ok($$select public.disband_team(t.team('Los Lobos'))$$, 'P0001', 'not_captain', 'ni disuelve');
select lives_ok($$select public.leave_team(t.team('Los Lobos'))$$, 'un integrante se va');
reset role;
select is(t.members('Los Lobos'), array[7001::bigint, 7002, 7008], 'quedan tres');
select t.act(7007);
select is(public.my_teams(), '[]'::jsonb, 'y ya no lo ve');
select lives_ok($$select public.create_team(2, 'Nuevos')$$, 'quien salio puede crear otro');

select t.act(7001);
select throws_ok($$select public.kick_member(t.team('Los Lobos'), 7001)$$, 'P0001', 'invalid_target', 'no se expulsa a si misma');
select throws_ok($$select public.kick_member(t.team('Los Lobos'), 7999)$$, 'P0001', 'not_member', 'ni a quien no esta');
select lives_ok($$select public.kick_member(t.team('Los Lobos'), 7008)$$, 'expulsa a 7008');
reset role;
select is(t.members('Los Lobos'), array[7001::bigint, 7002], 'quedan dos');
select t.act(7001);
select throws_ok($$select public.transfer_captain(t.team('Los Lobos'), 7001)$$, 'P0001', 'invalid_target', 'traspaso a si misma');
select throws_ok($$select public.transfer_captain(t.team('Los Lobos'), 7008)$$, 'P0001', 'not_member', 'traspaso a quien no es integrante');
select lives_ok($$select public.transfer_captain(t.team('Los Lobos'), 7002)$$, 'traspasa a Beto');
reset role;
select is(t.captain('Los Lobos'), 7002::bigint, 'Beto es capitan');
select t.act(7001);
select throws_ok($$select public.kick_member(t.team('Los Lobos'), 7002)$$, 'P0001', 'not_captain', 'Ana ya no puede expulsar');
select throws_ok($$select public.invite_to_team(t.team('Los Lobos'), 7010)$$, 'P0001', 'not_captain', 'ni invitar');
select lives_ok($$select public.leave_team(t.team('Los Lobos'))$$, 'ahora Ana puede irse');
select t.act(7002);
select lives_ok($$select public.invite_to_team(t.team('Los Lobos'), 7010)$$, 'Beto invita');
select lives_ok($$select public.disband_team(t.team('Los Lobos'))$$, 'y puede disolver');
reset role;
select is(t.team('Los Lobos'), null, 'el equipo ya no existe');
select is((select count(*)::int from public.team_members where steam_id in (7002)), 0, 'sin integrantes colgando');
select is((select count(*)::int from public.team_invites where to_steam = 7010), 0, 'ni invitaciones');
select t.act(7002);
select lives_ok($$select public.create_team(2, 'Los Lobos')$$, 'el nombre vuelve a estar libre');

select t.act(7004);
select throws_ok($$select public.disband_team(t.team('Cuervos'))$$, 'P0001', 'not_captain', 'Dani (integrante de Cuervos) no disuelve');
select t.act(7003);
select lives_ok($$select public.disband_team(t.team('Cuervos'))$$, 'Caro (capitana) si');

reset role;
select * from finish();
rollback;
